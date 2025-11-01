WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate hospital LOS in days
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE a.hadm_id = d.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('430','431','432','433','434','435','436','437','438','36234'))
          OR 
          (d.icd_version = 10 AND d.icd_code IN ('G45','G46','I60','I61','I62','I63','I64','I65','I66','I67','I68','I69'))
        )
    )
),

icu_status AS (
  SELECT 
    hadm_id,
    MAX(1) AS icu_flag  -- 1 if ICU stay exists
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),

comorbidities AS (
  SELECT 
    hadm_id,
    -- CKD flag
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code IN ('5851','5852','5853','5854','5855','5856','5859','586','V420','V451','V560','V561','V562','V563','V568')) 
               OR (icd_version = 10 AND icd_code IN ('N181','N182','N183','N184','N185','N186','N189','N19','Z490','Z491','Z492','Z940','Z992')) 
          THEN 1 ELSE 0 
        END) AS ckd_flag,
    -- Diabetes flag
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code IN ('25000','25001','25002','25003','25010','25011','25012','25013','25020','25021','25022','25023','25030','25031','25032','25033','25040','25041','25042','25043','25050','25051','25052','25053','25060','25061','25062','25063','25070','25071','25072','25073','25080','25081','25082','25083','25090','25091','25092','25093')) 
               OR (icd_version = 10 AND icd_code IN ('E100','E101','E106','E108','E109','E110','E111','E116','E118','E119','E120','E121','E126','E128','E129','E130','E131','E136','E138','E139','E140','E141','E146','E148','E149')) 
          THEN 1 ELSE 0 
        END) AS diabetes_flag,
    -- Comorbidity flags for index (5 conditions)
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code IN ('39891','40201','40211','40291','40401','40403','40411','40413','40491','40493','4254','4255','4257','4258','4259','428')) 
               OR (icd_version = 10 AND icd_code IN ('I099','I110','I130','I132','I255','I420','I425','I426','I427','I428','I429','I43','I50','P290')) 
          THEN 1 ELSE 0 
        END) AS chf_flag,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code IN ('4168','4169','490','491','492','493','494','495','496','500','501','502','503','504','505','5064','5081','5088')) 
               OR (icd_version = 10 AND icd_code IN ('I278','I279','J40','J41','J42','J43','J44','J45','J46','J47','J60','J61','J62','J63','J64','J65','J66','J67','J684','J701','J703')) 
          THEN 1 ELSE 0 
        END) AS pulmonary_flag,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code IN ('140','141','142','143','144','145','146','147','148','149','150','151','152','153','154','155','156','157','158','159','160','161','162','163','164','165','166','167','168','169','170','171','172','174','175','176','177','178','179','180','181','182','183','184','185','186','187','188','189','190','191','192','193','194','195','200','201','202','203','204','205','206','207','208','2386')) 
               OR (icd_version = 10 AND icd_code IN ('C00','C01','C02','C03','C04','C05','C06','C07','C08','C09','C10','C11','C12','C13','C14','C15','C16','C17','C18','C19','C20','C21','C22','C23','C24','C25','C26','C30','C31','C32','C33','C34','C37','C38','C39','C40','C41','C42','C43','C44','C45','C46','C47','C48','C49','C50','C51','C52','C53','C54','C55','C56','C57','C58','C60','C61','C62','C63','C64','C65','C66','C67','C68','C69','C70','C71','C72','C73','C74','C75','C76','C80','C81','C82','C83','C84','C85','C86','C88','C90','C91','C92','C93','C94','C95','C96','C97')) 
          THEN 1 ELSE 0 
        END) AS cancer_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

cohort_comorbid AS (
  SELECT 
    c.*,
    COALESCE(i.icu_flag, 0) AS icu_status,  -- 0 if no ICU stay
    CASE 
      WHEN c.los_days <= 5 THEN '<=5' 
      ELSE '>5' 
    END AS los_group,
    com.ckd_flag,
    com.diabetes_flag,
    -- Comorbidity count (0-5) and tertile
    (com.chf_flag + com.diabetes_flag + com.ckd_flag + com.pulmonary_flag + com.cancer_flag) AS comorbidity_count,
    NTILE(3) OVER (ORDER BY (com.chf_flag + com.diabetes_flag + com.ckd_flag + com.pulmonary_flag + com.cancer_flag)) AS comorbidity_tertile
  FROM cohort c
  LEFT JOIN icu_status i
    ON c.hadm_id = i.hadm_id
  LEFT JOIN comorbidities com
    ON c.hadm_id = com.hadm_id
)

SELECT 
  CASE icu_status 
    WHEN 1 THEN 'ICU' 
    ELSE 'Non-ICU' 
  END AS icu_group,
  los_group,
  comorbidity_tertile,
  COUNT(*) AS n_patients,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
  ROUND(100.0 * SUM(ckd_flag) / COUNT(*), 2) AS ckd_percent,
  ROUND(100.0 * SUM(diabetes_flag) / COUNT(*), 2) AS diabetes_percent
FROM cohort_comorbid
GROUP BY icu_group, los_group, comorbidity_tertile
ORDER BY icu_group, los_group, comorbidity_tertile;