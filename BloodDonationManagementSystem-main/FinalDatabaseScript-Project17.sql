use project_team17;


-------------------------------------------DATA--ENCRYPTION--------------------------------------------

----------INITIALIZE-ENCRYPTION-KEY------------
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Test_P@assword';
----------CREATE-CERTIFICATE-TO-PROTECT-KEY-----------
CREATE CERTIFICATE BloodbankCertificate
WITH SUBJECT = 'BloodBankDataEncryption',
EXPIRY_DATE = '2023-08-31';
-----------CREATE-SYMMETRIC-KEY-TO-ENCRYPT-DATA------------
CREATE SYMMETRIC KEY BloodEncryptionKey
WITH ALGORITHM = AES_128
ENCRYPTION BY CERTIFICATE bloodbankCertificate;



--------------------------------------------TABLE--CREATION--------------------------------------------

IF NOT EXISTS(SELECT * FROM sys.objects  WHERE name='PersonAddress' )
CREATE TABLE  PersonAddress (
	AddressID INT IDENTITY(10001,1) PRIMARY KEY, 
	AddressLine1 VARCHAR(50) NOT NULL,
	AddressLine2 VARCHAR(50), 
	City VARCHAR(20), 
	State VARCHAR(20), 
	Country VARCHAR(50), 
	ZipCode INT
);

IF NOT EXISTS(SELECT * FROM sys.objects  WHERE name='Person' )
CREATE TABLE  Person ( 
	PersonID INT IDENTITY(20001,1) PRIMARY KEY,
	FirstName VARCHAR(50) NOT NULL,
	LastName VARCHAR(30),
	BloodType VARCHAR(3),
	AddressID INT NOT NULL FOREIGN KEY REFERENCES PersonAddress(AddressID),
	SSN VARBINARY(250),
	Gender VARCHAR(10),
	Email VARCHAR(50),
	PhoneNumber BIGINT,
	DOB DATE,
	Age AS DATEDIFF(hour, DOB, GETDATE())/8766
);

IF NOT EXISTS(SELECT * FROM sys.objects  WHERE name='Donor' )
CREATE TABLE  Donor (
	DonorID INT IDENTITY(60001,1) PRIMARY KEY,  --- put a constraint that person's age is not greater than 70(any number that we decide)
	PersonID INT NOT NULL FOREIGN KEY REFERENCES Person(PersonID), 
	EmergencyAvailability BIT
);


IF NOT EXISTS(SELECT * FROM sys.objects  WHERE name='Receiver' )
CREATE TABLE  Receiver ( 
	ReceiverID INT IDENTITY PRIMARY KEY,
	PersonID INT NOT NULL FOREIGN KEY REFERENCES Person(PersonID)
);

IF NOT EXISTS(SELECT * FROM sys.objects  WHERE name='FamilyMember' )
CREATE TABLE  FamilyMember ( 
	RelativeID INT NOT NULL PRIMARY KEY FOREIGN KEY REFERENCES Person(PersonID),
	DonorID INT FOREIGN KEY REFERENCES Donor(DonorID)
);

IF NOT EXISTS(SELECT * FROM sys.objects  WHERE name='Location' )
CREATE TABLE Location ( 
	LocationID INT IDENTITY PRIMARY KEY, 
	AddressLine1 VARCHAR(50) NOT NULL,
	AddressLine2 VARCHAR(50), 
	City VARCHAR(20), 
	State VARCHAR(20), 
	Country VARCHAR(50), 
	ZipCode INT
);

IF NOT EXISTS(SELECT * FROM sys.objects  WHERE name='Organization' )
CREATE TABLE  Organization (
	OrganizationID INT IDENTITY PRIMARY KEY,
	OrganizationName VARCHAR(50),
	LocationID INT FOREIGN KEY REFERENCES Location(LocationID) 
);

IF NOT EXISTS(SELECT * FROM sys.objects  WHERE name='DonationDrive' )
CREATE TABLE DonationDrive ( 
	DriveID INT IDENTITY PRIMARY KEY,
	OrganizationID INT FOREIGN KEY REFERENCES Organization(OrganizationID),
	LocationID INT FOREIGN KEY REFERENCES Location(LocationID), 
	DriveDate DATE
);

IF NOT EXISTS(SELECT * FROM sys.objects  WHERE name='BloodSample' )
CREATE TABLE BloodSample  ( 
	BloodSampleID INT IDENTITY PRIMARY KEY,
	DonationDate DATE, --- validate here using DonationHistory that donationdate shouldn't be less than nextduedate for a donor(keeping it optional for now)
	ExpiryDate as DATEADD(MONTH, 3, DonationDate),
	BloodType VARCHAR(3)
); --need 1 trigger here to populate ExpiryDate



IF NOT EXISTS(SELECT * FROM sys.objects  WHERE name='DonationHistory' )
CREATE TABLE  DonationHistory (
	DriveID INT NOT NULL FOREIGN KEY REFERENCES DonationDrive(DriveID),
	DonorID INT NOT NULL FOREIGN KEY REFERENCES Donor(DonorID),
	BloodSampleID INT FOREIGN KEY REFERENCES BloodSample(BloodSampleID),
	NextDueDate DATE,  -- create trigger to populate this 
	CONSTRAINT PKDonationHistory PRIMARY KEY CLUSTERED (DriveID, DonorID)
);

IF NOT EXISTS(SELECT * FROM sys.objects  WHERE name='Hospital' )
	CREATE TABLE  Hospital ( 
	HospitalID INT IDENTITY PRIMARY KEY,
	LocationID INT FOREIGN KEY REFERENCES Location(LocationID), 
	HospitalName VARCHAR(50),  -- why is hospitalname int in the erd 
	ContactInfo BIGINT,
	Email VARCHAR(50)
);

IF NOT EXISTS(SELECT * FROM sys.objects  WHERE name='Nurse' )
CREATE TABLE Nurse  (
	NurseID INT IDENTITY PRIMARY KEY, 
	HospitalID INT NOT NULL FOREIGN KEY REFERENCES Hospital(HospitalID),
	PersonID INT NOT NULL FOREIGN KEY REFERENCES Person(PersonID)
);


IF NOT EXISTS(SELECT * FROM sys.objects  WHERE name='SampleScreening' )
CREATE TABLE SampleScreening  ( 
	BloodSampleID INT PRIMARY KEY FOREIGN KEY REFERENCES BloodSample(BloodSampleID),
	HospitalID INT NOT NULL FOREIGN KEY REFERENCES Hospital(HospitalID),
	TransferEligibility BIT,
	Coagulation BIT,
	Haemoglobin DECIMAL
);

IF NOT EXISTS(SELECT * FROM sys.objects  WHERE name='BloodAvailability' )
CREATE TABLE BloodAvailability  ( 
	BloodSampleID INT PRIMARY KEY FOREIGN KEY REFERENCES SampleScreening(BloodSampleID),
	HospitalID INT NOT NULL FOREIGN KEY REFERENCES Hospital(HospitalID),
	BloodType VARCHAR(3)
);

IF NOT EXISTS(SELECT * FROM sys.objects  WHERE name='PaymentInfo' ) -- need a procedure/trigger in this table to make amount as 0
CREATE TABLE  PaymentInfo ( 
	PaymentID INT IDENTITY PRIMARY KEY, 
	PaymentDate DATE, 
	Units INT CHECK(Units > 0),  
	Amount DECIMAL
);


IF NOT EXISTS(SELECT * FROM sys.objects  WHERE name='TransfusionRecords' )
CREATE TABLE  TransfusionRecords ( 
	BloodSampleID INT NOT NULL FOREIGN KEY REFERENCES BloodAvailability(BloodSampleID),
	ReceiverID INT NOT NULL FOREIGN KEY REFERENCES Receiver(ReceiverID),
	HospitalID INT NOT NULL FOREIGN KEY REFERENCES Hospital(HospitalID),
	PaymentID INT NOT NULL FOREIGN KEY REFERENCES PaymentInfo(PaymentID),
	NurseID INT NOT NULL FOREIGN KEY REFERENCES Nurse(NurseID),
	TransfusionDate DATE,
	BloodTypeReceived VARCHAR(3),--put a trigger/check here to valid compatibilty
	CONSTRAINT PKTransfusionRecords PRIMARY KEY CLUSTERED (BloodSampleID, ReceiverID)
);

-----------------------------------------------------UDF - CONSTRAINTS -------------------------------------------------------

---------CHECKAGE-------------
GO
CREATE OR ALTER FUNCTION CheckAge(@PersonID int)
RETURNS smallint
AS
BEGIN
   DECLARE @Count smallint;
   SET @count = 0;
	SELECT @Count = IIF(Age>70,1,0)
		  FROM Person
          WHERE PersonID = @PersonID;
   RETURN @Count;
END;
GO

ALTER TABLE Donor ADD CONSTRAINT CheckAgeConstraint CHECK(dbo.CheckAge(PersonID) = 0);
-------CHECKDUEDATE--------
GO
CREATE OR ALTER FUNCTION CheckDueDate(@DonorID int, @DriveID int)
RETURNS smallint
AS
BEGIN
   DECLARE @Count smallint;
   SET @count = 0;

   WITH maxdate AS
   (
	SELECT MAX(NextDueDate) as maxdate FROM DonationHistory WHERE DonorID = @DonorID GROUP BY DonorID
   )

	SELECT @Count = IIF(DriveDate<(SELECT maxdate FROM maxdate),1,0)
		  FROM DonationDrive
          WHERE DriveID = @DriveID;
   RETURN @Count;
END;
GO

ALTER TABLE DonationHistory ADD CONSTRAINT ChecDueDateConstraint CHECK(dbo.CheckDueDate(DonorID,DriveID) = 0);
-------CHECKPAYMENTDATE--------
GO
CREATE OR ALTER FUNCTION CheckPaymentDate(@PaymentID int)
RETURNS smallint
AS
BEGIN
   DECLARE @Count smallint;
   SET @count = 0;
	
	SELECT @Count = IIF(pinfo.PaymentDate  >= tr.TransfusionDate,1,0)
		  FROM TransfusionRecords tr JOIN PaymentInfo pinfo ON tr.PaymentID = pinfo.PaymentID
          WHERE tr.PaymentID = @PaymentID;
   RETURN @Count;
END;
GO

ALTER TABLE TransfusionRecords DROP CONSTRAINT CheckPaymentDateConstraint;

ALTER TABLE TransfusionRecords ADD CONSTRAINT CheckPaymentDateConstraint CHECK(dbo.CheckPaymentDate(PaymentID) = 1);
--------------------------------Triggers------------------------------------------

---------------Populate Expiry Date------------------
--DROP TRIGGER CalcExpiryDate;
/*GO
CREATE OR ALTER TRIGGER CalcExpiryDate
on dbo.BloodSample
AFTER INSERT , UPDATE 
AS
BEGIN
	 UPDATE BloodSample SET ExpiryDate = DATEADD(MONTH, 3, DonationDate)
	 
END
GO*/

-----------------NextDueDate--------------
GO
CREATE or ALTER TRIGGER NextDueDate
on DonationHistory
AFTER INSERT,UPDATE
AS
BEGIN
	 DECLARE @DonationDate date
	 SET @DonationDate  =  (Select DonationDate From BloodSample WHERE BloodSampleID = (Select BloodSampleID From inserted)) 
	 update DonationHistory
	 SET NextDueDate = DATEADD(MONTH, 2, @DonationDate)
	 WHERE BloodSampleID =   (Select BloodSampleID From inserted) 
END
GO

------------------UpdatePayment-------------------
GO
CREATE or ALTER TRIGGER updatepayment 
ON TransfusionRecords
AFTER INSERT, UPDATE 
AS
BEGIN
	DECLARE @ReceiverIsFamily BINARY
	DECLARE @PaymentID INT 
	
	SET @ReceiverIsFamily = IIF( (SELECT ReceiverID From inserted)  IN  (SELECT ReceiverID From Receiver r JOIN FamilyMember fm ON r.PersonID = fm.RelativeID), 1, 0)
	SET @PaymentID = (SELECT PaymentID From inserted)
	
	IF @ReceiverIsFamily = 0
	
	  BEGIN
		UPDATE PaymentInfo SET Amount = (SELECT Units From PaymentInfo WHERE PaymentID = @PaymentID) * 2000
		WHERE PaymentID = @PaymentID
	  END
	  
	ELSE 
	
	   BEGIN
	    UPDATE PaymentInfo SET Amount = 0 WHERE PaymentID = @PaymentID
	   END
	
END
GO


--------------------------------------------------Trigger-Data-Encryption--------------------------------------------------

CREATE or ALTER TRIGGER UpdateSSN ON 
dbo.Person
AFTER INSERT, UPDATE
AS 
BEGIN
		OPEN SYMMETRIC KEY BloodEncryptionKey
		DECRYPTION BY CERTIFICATE BloodbankCertificate;	
		
		update Person SET SSN  = EncryptByKey(Key_GUID(N'BloodEncryptionKey'),CONVERT(VARBINARY, SSN));

		CLOSE SYMMETRIC KEY BloodEncryptionKey;
END


---------------------------------------------------Auto-Fill-Table----------------------------------------------------
GO
CREATE OR ALTER TRIGGER SetTransferEligibility ON 
dbo.SampleScreening
AFTER INSERT 
AS 
BEGIN
	
	DECLARE @Availabilty BIT;

	SET @Availabilty = 0

    IF ((SELECT Coagulation FROM inserted) = 0 AND (SELECT Haemoglobin FROM inserted) >12.5)
    BEGIN
     SET @Availabilty = 1
    END 
      
      
    UPDATE dbo.SampleScreening SET TransferEligibility = @Availabilty 
	WHERE BloodSampleID= (SELECT BloodSampleID FROM inserted) 

END
GO
-------------------------------------------------------------------------------------------------


GO
CREATE  OR ALTER TRIGGER UpdateAvailbility ON 
SampleScreening
AFTER UPDATE 
AS 
BEGIN
	DECLARE @BloodType VARCHAR(3)
	DECLARE @BloodSampleID INT
	DECLARE @TransferEligibility BIT
	DECLARE @HospitalID INT

	SELECT @TransferEligibility = INSERTED.TransferEligibility FROM INSERTED

	SELECT @BloodSampleID = INSERTED.BloodSampleID FROM INSERTED

	SELECT @HospitalID = INSERTED.HospitalID FROM INSERTED
	
	SELECT @BloodType = (SELECT BloodType FROM BloodSample WHERE BloodSampleID= @BloodSampleID )

	IF @TransferEligibility = 1
	BEGIN
		INSERT INTO dbo.BloodAvailability VALUES( @BloodSampleID, @HospitalID,@BloodType )
	END
END
GO

-----------------------------------------------------------Views--------------------------------------------------------------------

------------------------View1 - TopBloodDonatedForEachZipCode---------------------------
CREATE VIEW [TopBloodDonatedForEachZipCode] AS
SELECT 
	r.BloodType,
	r.CountOfBloodDonated,
	r.ZipCode
	FROM
	(
		SELECT DISTINCT p.BloodType ,
		COUNT (p.BloodType) as CountOfBloodDonated,
		DENSE_RANK() over (PARTITION BY l.zipcode ORDER BY COUNT(p.bloodType) desc) as rn,
		l.ZipCode
		FROM Person p 
		INNER JOIN Donor d on d.PersonID = p.PersonID
		INNER JOIN DonationHistory dh on dh.DonorID = d.DonorID
		INNER JOIN DonationDrive dd on dd.driveId = dh.DriveID
		INNER JOIN Location l on l.LocationID = dd.LocationID
		GROUP BY l.ZipCode , p.BloodType
		) r
		WHERE r.rn =1;	

SELECT * FROM TopBloodDonatedForEachZipCode;

---------------------View2 - CollectedBloodNeverDonated---------------------

CREATE VIEW  [CollectedBloodNeverDonated] AS
SELECT 
	bs.BloodSampleID ,
	tr.ReceiverID , 
	tr.TransfusionDate
FROM DonationDrive dd
LEFT JOIN DonationHistory dh on dh.DriveID = dd.DriveID
LEFT JOIN BloodSample bs on bs.BloodSampleID = dh.BloodSampleID
LEFT JOIN TransfusionRecords tr on tr.BloodSampleID = bs.BloodSampleID
WHERE tr.ReceiverID IS NULL;

SELECT * FROM CollectedBloodNeverDonated;

-----------------------View3 - Count of transfusion per hospital --------------------

CREATE VIEW CountOfTransfusionPerHospital AS
SELECT h.HospitalName, count(*) AS 'Number_Of_Transfusion'
FROM TransfusionRecords tr JOIN Hospital h 
	ON tr.HospitalID = h.HospitalID
GROUP BY h.HospitalID,h.HospitalName;

SELECT * FROM CountOfTransfusionPerHospital;

-----------------------View4 - Donation count for every organization --------------------

CREATE VIEW DonationCountForEveryOrganization AS
SELECT o.OrganizationName,count(dh.BloodSampleID) AS 'Donation_Count'
FROM Organization o JOIN DonationDrive d 
	ON o.OrganizationID = d.OrganizationID
JOIN DonationHistory dh 
	ON d.DriveID = dh.DriveID
GROUP BY o.OrganizationName;

SELECT * FROM DonationCountForEveryOrganization;

---------------------------View5 - % of Blood Used---------------------------------------------

CREATE OR ALTER VIEW PercentageOfBloodExpired AS
	WITH totalblood AS
	(
		SELECT CAST(COUNT(ba.BloodSampleID) AS DECIMAL(2)) AS bloodcount
		FROM BloodAvailability ba JOIN BloodSample bs
			ON ba.BloodSampleID = bs.BloodSampleID
	), bloodnotused AS
	(
		SELECT ba.BloodSampleID
		FROM BloodAvailability ba LEFT JOIN TransfusionRecords ta
			ON ba.BloodSampleID = ta.BloodSampleID
		WHERE ta.BloodSampleID IS NULL
	),bloodexpired AS
	(
		SELECT CAST(Count(bs.BloodSampleID) AS DECIMAL(2)) AS bloodexpired 
		FROM BloodSample bs JOIN bloodnotused bnu
			ON bs.BloodSampleID = bnu.BloodSampleID
		WHERE bs.ExpiryDate > getDate()
	)

	SELECT CONCAT(CAST((((select bloodexpired from bloodexpired)/(select bloodcount from totalblood)) * 100) AS VARCHAR),' %') AS PercentageOfBloodExpired ;

SELECT * FROM PercentageOfBloodExpired;



SELECT * FROM Person