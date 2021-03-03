use finalProject;
start transaction;

DELIMITER //
drop procedure if exists register//
CREATE PROCEDURE register(
	in username varchar(30),
    in passwd varchar(30),
    in fname varchar(20),
    in sname varchar(20),
    in nationalId varchar(10),
    in accountType enum("teacher", "student", "others", "manager", "lib"),
    out result varchar(500)
)
BEGIN
    SET @usernameCount = 0;
	SELECT count(*) into @usernameCount FROM Person WHERE cast(Person.username AS CHAR(30)) = lower(username);
    
    SET @isPasswordValid = 0;
    SELECT ((passwd regexp '[[:digit:]]+') AND (passwd regexp '[[:alpha:]]+')) INTO @isPasswordValid;
    
	IF CHAR_LENGTH(passwd) < 8 THEN
		set @isPasswordValid = 0;
	END IF;
    
 	IF CHAR_LENGTH(username) >= 6 AND @isPasswordValid >= 1 AND @usernameCount = 0 THEN
		INSERT INTO Person(nationalId, firstName, secondName, username, passwd)
			VALUES (nationalId, fname, sname, CAST(username AS BINARY(30)), MD5(passwd));
        
		INSERT INTO Account (Account.nationalId, balance , creationDate , accountType)
			VALUES (nationalId, 0, CURRENT_DATE() ,accountType);
        
		SET result = "Success. Account created";
	ELSEIF @usernameCount > 0 THEN
		SET result = "Username already exists";
	ELSEIF CHAR_LENGTH(username) < 6 THEN
    	SET result = "Username must be at leaset 6 letters";
	ELSEIF CHAR_LENGTH(passwd) < 8 THEN
    	SET result = "Password must be at leaset 8 letters&numbers";
	ELSE
		SET result = "Password must be a combination of letters and numbers";
 	END IF;

END //


drop procedure if exists login//
CREATE PROCEDURE login(
	in username varchar(30),
    in passwd varchar(30),
    out result varchar(500),
    out token varchar(500)
)
BEGIN

    SET @loginSuccess = 0;
	SELECT count(*) into @loginSuccess FROM Person WHERE cast(Person.username AS CHAR(30)) = username AND Person.passwd = MD5(passwd);
    
    -- TODO: Check already logged in
    
 	IF @loginSuccess = 1 THEN
		INSERT INTO LoggedIn(nationalId, token)
			VALUES((SELECT nationalId FROM Person WHERE cast(Person.username AS CHAR(30)) = username ), MD5(CONCAT(passwd , username, NOW())));
        set result = "success";
        set token = MD5(CONCAT(passwd , username, NOW()));
	ELSE
		set result = "Wrong username or password!";
 	END IF;

END //

drop procedure if exists logout//
CREATE PROCEDURE logout(
	in token varchar(500)
)
BEGIN
	IF (EXISTS (SELECT * FROM LoggedIn WHERE LoggedIn.token = token)) THEN
		DELETE FROM LoggedIn WHERE LoggedIn.token = token;
    END IF;
END //

drop procedure if exists addBook//
CREATE PROCEDURE addBook(
	in token varchar(500),
    in bookId int,
    in volume int,
    in edition int,
    in title varchar(500),
    in category varchar(20),
    in bookType enum("uni", "source", "others"), -- uni, source, others
    in publisher varchar(20),
	in writer varchar(50),
    in releaseDate Date,
    in pages int,
    in cost int,
    out _status varchar(500)
)
BEGIN
	IF (EXISTS (SELECT * FROM LoggedIn WHERE LoggedIn.token = token)) THEN
		SET @accType = "";
		
        SELECT accountType INTO @accType FROM Account 
        WHERE Account.nationalId = (SELECT nationalId FROM LoggedIn WHERE LoggedIn.token = token);
        
        IF @accType = "lib" OR @accType = "manager" THEN
			
            -- Insert book if not exist
            IF (NOT EXISTS (SELECT * FROM Book WHERE Book.bookId = bookId AND Book.volume = volume AND Book.edition = edition)) THEN
				INSERT INTO Book(bookId, volume, edition, title, category, bookType, publisher, writer, releaseDate, pages, cost)
					VALUES(bookId, volume, edition, title, category, bookType, publisher, writer, releaseDate, pages, cost);
            END IF;
            
            IF( EXISTS(SELECT * FROM Inventory WHERE Inventory.bookId = (SELECT bookId From Book WHERE Book.bookId = bookId) AND Inventory.edition = edition)) THEN
				SET @newCount = 1;
                SELECT count INTO @newCount FROM Inventory WHERE Inventory.bookId = (SELECT bookId From Book WHERE Book.bookId = bookId) AND Inventory.edition = edition;
				
                UPDATE Inventory SET count = @newCount + 1
                WHERE Inventory.bookId = (SELECT bookId From Book WHERE Book.bookId = bookId) AND Inventory.edition = edition;
            ELSE
				INSERT INTO Inventory(bookId, edition, count)
					VALUES((SELECT bookId From Book WHERE Book.bookId = bookId), edition, 1);
            END IF;
			set _status = "success";
        ELSE
			set _status = CONCAT("Access denid: ", @accType);
        END IF;
	ELSE
		SET _status = "User is not logged in";
    END IF;
END //

drop procedure if exists searchBook//
CREATE PROCEDURE searchBook(
	in token varchar(500),
    in edition int,
    in title varchar(500),
	in writer varchar(50),
    in releaseDate Date,
    out _status varchar(500)
)
BEGIN
	IF (EXISTS (SELECT * FROM LoggedIn WHERE LoggedIn.token = token)) THEN
		SELECT * FROM Book 
		WHERE (edition IS NULL OR Book.edition = edition) AND 
			  (title IS NULL OR Book.title = title) AND 
			  (writer IS NULL OR Book.writer = writer) AND 
			  (releaseDate IS NULL OR Book.releaseDate = releaseDate) ORDER BY Book.title;
		set _status = "success";
	ELSE
		set _status = "Please log in first";
	END IF;
END //

CREATE PROCEDURE checkHistory(
    in nationalId varchar(10),
    out lateTimes int
)
BEGIN
	SELECT COUNT(*) INTO lateTimes FROM Borrow 
    WHERE Borrow.nationalId = nationalId AND 
		  (Borrow.takeDate >= date_sub(CURRENT_DATE(), INTERVAL 60 DAY)) AND
          ((Borrow.returnDate != NULL AND datediff(Borrow.returnDate, Borrow.takeDate) > Borrow.legalDuration) OR DATEDIFF(CURRENT_DATE(), Borrow.takeDate) > Borrow.legalDuration)
    ORDER BY Borrow.takeDate DESC;
END//

drop procedure if exists borrowBook//
CREATE PROCEDURE borrowBook(
	in token varchar(500),
    in bookTitle varchar(500),
    in bookEdition int,
    out _status varchar(500)
)
BEGIN
	IF (EXISTS (SELECT * FROM LoggedIn WHERE LoggedIn.token = token)) THEN
		SET @accType = "", @balance = 0, @natId = 0, @suspensionDate = NULL;
		
        SELECT accountType, balance, nationalId, suspensionDate INTO @accType, @balance, @natId, @sispensionDate FROM Account 
        WHERE Account.nationalId = (SELECT nationalId FROM LoggedIn WHERE LoggedIn.token = token);
        
        SET @bookType="", @bookId = 0, @edition = 0, @cost = 0;
        SELECT bookType, bookId, edition, cost INTO @bookType, @bookId, @edition, @cost FROM Book WHERE Book.title = bookTitle AND Book.edition = bookEdition;
        
		-- start checking:
        IF @accType = "teacher" OR 
	    (@accType = "student" AND @bookType != "source") OR 
	    (@accType = "others" AND @bookType = "others") THEN
			
			IF @balance >= (@cost * 5 / 100) THEN
				IF(EXISTS(SELECT * FROM Inventory WHERE Inventory.bookId = @bookId AND Inventory.edition = @edition)) THEN
					IF(@suspensionDate != NULL AND @susnpensionDate > CURRENT_DATE()) THEN
						SET _status = "You account is suspended";
					ELSE
						IF @suspensionDate != NULL THEN
							SET @suspensionDate = NULL;
                            UPDATE Account SET Account.suspensionDate = NULL WHERE Account.nationalId = @natId;
                        END IF;
                        
						call checkHistory(@natId, @lateTimes);
                        IF @lateTimes >= 4 THEN
							SET _status = "Delay in returning books >= 4. Account suspended";
                            UPDATE Account SET Account.suspensionDate = DATE_ADD(CURRENT_DATE(), INTERVAL 30 DAY) WHERE Account.nationalId = @natId;
                        ELSE
							SET @returnDate = NULL, @counter = 0;
							SELECT returnDate, COUNT(*) into @returnDate, @counter FROM Borrow WHERE Borrow.nationalId = @natId AND Borrow.bookId = @bookId AND Borrow.edition = @edition;
							
                            IF @counter = 0 OR @returnDate != NULL THEN
								-- finaly success!
                                INSERT INTO Borrow(bookId, edition, nationalId, takeDate, returnDate, legalDuration, borrowCost)
									VALUES(@bookId, @edition, @natId, current_date(), NULL, 10, @cost * 5 / 100);
								
                                UPDATE Account SET Account.balance = @balance - (@cost * 5/100)
									WHERE Account.nationalId = @natId;
								
                                SET @invCount = 0;
                                SELECT count into @invCount FROM Inventory WHERE Inventory.bookId = @bookRow.bookId AND Inventory.edition = @bookRow.edition;
                                
                                IF @invCount <= 1 THEN
									DELETE FROM Inventory WHERE Inventory.bookId = @bookId AND Inventory.edition = @edition;
                                ELSE
									UPDATE Inventory SET Inventory.count = @invCount - 1
										WHERE Inventory.bookId = @bookId AND Inventory.edition = @edition;
                                END IF;
                                
								SET _status = "success";		
							ELSE
								SET _status = "U Already have borrowed the book";
                            END IF;
							
                        END IF;
                        
						
                    END IF;
                    
                    
					
                ELSE
					SET _status = "Book doesn't exist in Inventory";
                END IF;
				
			ELSE
				SET _status = "Not enough money";
			END IF;
        ELSE
			SET _status = CONCAT("permission denid: ", @accType," ",@bookType);
	    END IF;
		call addLog(_status, @natId, @bookId, @edition);
    ELSE
		set _status = "Please log in first";
    END IF;
    
END //

CREATE PROCEDURE increaseBalance(
	in token varchar(500),
    in amount int,
    out _status varchar(500)
)
BEGIN
	IF (EXISTS (SELECT * FROM LoggedIn WHERE LoggedIn.token = token)) THEN
		IF amount <= 0 THEN
			set _status = "Amount must be greater than 0";
        ELSE
			SELECT @natId := nationalId FROM LoggedIn WHERE LoggedIn.token = token;
		
			SELECT @oldBalance := balance FROM Account WHERE Account.nationalId = @natId;
		
			UPDATE Account SET balance = @oldBalance + amount
					WHERE Account.nationalId = @natId;
			set _status = "success";
		END IF;
    ELSE
		set _status = "Please log in first";
    END IF;
END//

drop procedure if exists addLog//
CREATE PROCEDURE addLog(
    in msg varchar(500),
    in nationalId varchar(10),
    in bookId int,
    in edition int
)
BEGIN
	INSERT INTO LibLog(nationalId, bookId, edition, msg, msgDate)
		VALUES(nationalId, bookId, edition, msg, CURRENT_DATE());
END//

CREATE PROCEDURE returnBook(
	in token varchar(500),
    in bookTitle varchar(500),
    in bookEdition int,
    out _status varchar(500)
)
BEGIN
	IF (EXISTS (SELECT * FROM LoggedIn WHERE LoggedIn.token = token)) THEN
		SET _status = "";
    END IF;
	
END //

DELIMITER ;
-- delete from Person where 1 = 1;
call register("libuser1", "username1", "ali", "mohammadi", "0000000001", "lib", @Res);
call register("normalUser", "Myuserddd2", "mohammad", "Heydari", "0000000002", "others", @Res2);
call register("thisisuser", "thisisuser1", "Ebi", "Adib", "0000000003", "student", @Res3);
call register("pwdzpwdz", "pwdzpwdz0", "mmd", "smf", "0000000004", "teacher", @Res4);
call register("adminadmin", "adminadmin0", "reza", "sinaii", "0000000005", "manager", @Res5);
call register("thisisme", "thisisme2", "akbar", "oooo", "0000000006", "student", @Res6);
select @Res2;

call login("libuser1", "username1", @R, @token);
call login("normalUser", "Myuserddd2", @R, @token2);
call login("thisisuser", "thisisuser1", @R, @token3);
call login("pwdzpwdz", "pwdzpwdz0", @R, @token4);
select @R;
call logout(@token);
call logout(@token2);
select * from Person;
select * from Account;
select * from LoggedIn;
select @token;
call addBook(@token, 0, 0, 1000,"TitleBook", "Drama", "uni", "BookPublisher","John Sina", '2000-01,01' , 110, 200, @_status);
call addBook(@token, 0, 0, 1000,"TitleBook", "Drama", "uni", "BookPublisher","John Sina", '2000-01,01' , 110, 200, @_status);
call addBook(@token, 2, 0, 1000,"itsBook", "Drama", "others", "BookPublisher","John notsina", '2000-02,01' , 110, 200, @_status);
call addBook(@token, 1, 0, 1000,"newBook", "Horor", "source", "BookPublisher2","Mosa Kazemi", '2020-05-02' ,94, 150, @_status);



select * from Book;
select * from Inventory;
select @_status;

call searchBook(@token,1000, "TitleBook", "John Sina", '2000-01-01', @_s);
select @_s;

call increaseBalance(@token2, 100, @_stat);

select * from Account;

call increaseBalance(@token3, 10, @_stat);
call borrowBook(@token2, "itsBook", 1000, @borrowStatus);

call increaseBalance(@token4, 1000, @_stat);
call borrowBook(@token4, "newBook", 1000, @borrowStatus);

Select @borrowStatus;

select * from LibLog;
select * from Borrow;
delete from Borrow where bookId = 2;
select * from Inventory;
select * from Account;