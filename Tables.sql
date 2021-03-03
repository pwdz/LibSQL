create table Person(
	nationalId varchar(10) not null unique,
    firstName varchar(20),
    secondName varchar(20),
    username varbinary (30),
    passwd varchar(500),
   primary key (nationalId)
);

create table Account(
	nationalId varchar(10) not null unique,
	balance Numeric(10,5) default 0,
	creationDate Date,
    accountType enum("teacher", "student","others", "manager", "lib"),
    suspensionDate Date,
    primary key (nationalId),
    foreign key (nationalId) references Person(nationalId)
);

create table Borrow(
	bookId int not null,
    edition int not null,
    nationalId varchar(10) not null,
    takeDate Date,
    returnDate Date,
    legalDuration int,
    borrowCost Numeric(10,5)
);

create table Book(
	bookId int not null unique,
    volume int default 0,
    edition int not null,
    title varchar(500),
    category varchar(20),
    bookType enum("uni", "source", "others"), -- uni, source, others
    publisher varchar(20),
    writer varchar(50),
    releaseDate Date,
    pages int,
    cost int,
    primary key (bookId, volume, edition)
);

create table Inventory(
	bookId int not null,
    edition int not null,
    count int default 0,
	primary key (bookId, edition),
	foreign key(bookId) references Book(bookId)
);

create table LoggedIn(
	nationalId varchar(10) not null unique,
    token varchar(500),
    primary key(token),
	foreign key(nationalId) references Person(nationalId)
);

create table LibLog(
	nationalId varchar(10) not null,
    bookId int not null,
    edition int not null,
    msg varchar(500),
    msgDate Date
);