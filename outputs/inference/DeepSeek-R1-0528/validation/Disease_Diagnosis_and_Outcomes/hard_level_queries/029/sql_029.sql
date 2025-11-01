WITH pneumonia_cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.deathtime,
    adm.hospital_expire_flag,
    p.gender, 
    p.dod,
    -- Calculate exact age at admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        diag.subject_id = adm.subject_id 
        AND diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code IN ('480','481','482','483','484','485','486','4870'))
          OR (diag.icd_version = 10 AND diag.icd_code IN ('J12','J13','J14','J15','J16','J17','J18','J690'))
        )
    )
), 
filtered_cohort AS (
  SELECT *
  FROM pneumonia_cohort
  WHERE age_at_admission BETWEEN 82 AND 92
),
comorbidities AS (
  SELECT 
    fc.subject_id,
    fc.hadm_id,
    -- CHF flags
    MAX(CASE 
      WHEN (diag.icd_version = 9 AND diag.icd_code IN ('39891','40201','40211','40291','40401','40403','40411','40413','40491','40493','4254','4255','4257','4258','4259','428')) 
      OR (diag.icd_version = 10 AND diag.icd_code IN ('I099','I110','I130','I132','I255','I420','I425','I426','I427','I428','I429','I43','I50','P290')) 
      THEN 1 ELSE 0 END) AS chf,
    -- Cerebrovascular flags
    MAX(CASE 
      WHEN (diag.icd_version = 9 AND diag.icd_code IN ('36234','430','431','432','433','434','435','436','437','438')) 
      OR (diag.icd_version = 10 AND diag.icd_code IN ('G45','G46','H340','I60','I61','I62','I63','I64','I65','I66','I67','I68','I69')) 
      THEN 1 ELSE 0 END) AS cerebrovascular,
    -- Renal failure flags
    MAX(CASE 
      WHEN (diag.icd_version = 9 AND diag.icd_code IN ('40301','40311','40391','40402','40403','40412','40413','40492','40493','5853','5854','5855','5856','5859','586','V420','V451','V560','V568')) 
      OR (diag.icd_version = 10 AND diag.icd_code IN ('I120','I131','N032','N033','N034','N035','N036','N037','N052','N053','N054','N055','N056','N057','N18','N19','N250','Z490','Z491','Z492','Z940','Z992')) 
      THEN 1 ELSE 0 END) AS renal,
    -- Malignancy flags
    MAX(CASE 
      WHEN (diag.icd_version = 9 AND diag.icd_code IN ('140','141','142','143','144','145','146','147','148','149','150','151','152','153','154','155','156','157','158','159','160','161','162','163','164','165','166','167','168','169','170','171','172','174','175','176','177','178','179','180','181','182','183','184','185','186','187','188','189','190','191','192','193','194','195','196','197','198','199','200','201','202','203','204','205','206','207','208')) 
      OR (diag.icd_version = 10 AND diag.icd_code IN ('C00','C01','C02','C03','C04','C05','C06','C07','C08','C09','C10','C11','C12','C13','C14','C15','C16','C17','C18','C19','C20','C21','C22','C23','C24','C25','C26','C30','C31','C32','C33','C34','C37','C38','C39','C40','C41','C43','C45','C46','C47','C48','C49','C50','C51','C52','C53','C54','C55','C56','C57','C58','C60','C61','C62','C63','C64','C65','C66','C67','C68','C69','C70','C71','C72','C73','C74','C75','C76','C80','C81','C82','C83','C84','C85','C86','C88','C90','C91','C92','C93','C94','C95','C96','C97')) 
      THEN 1 ELSE 0 END) AS malignancy
  FROM filtered_cohort fc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON fc.subject_id = diag.subject_id AND fc.hadm_id = diag.hadm_id
  GROUP BY fc.subject_id, fc.hadm_id
),
composite_score AS (
  SELECT 
    fc.*,
    com.chf,
    com.cerebrovascular,
    com.renal,
    com.malignancy,
    -- Calculate composite score (0-4)
    (CASE WHEN age_at_admission >= 85 THEN 1 ELSE 0 END) 
    + com.chf 
    + com.cerebrovascular 
    + com.renal 
    + com.malignancy AS risk_score
  FROM filtered_cohort fc
  INNER JOIN comorbidities com
    ON fc.subject_id = com.subject_id AND fc.hadm_id = com.hadm_id
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS risk_quintile
  FROM composite_score
),
complications AS (
  SELECT 
    q.subject_id,
    q.hadm_id,
    -- Cardiovascular complications (AMI, HF, arrest)
    MAX(CASE 
      WHEN (diag.icd_version = 9 AND (diag.icd_code LIKE '410%' OR diag.icd_code LIKE '428%' OR diag.icd_code = '4275')) 
      OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%' OR diag.icd_code LIKE 'I50%' OR diag.icd_code LIKE 'I46%')) 
      THEN 1 ELSE 0 END) AS cardiovascular_comp,
    -- Neurologic complications (stroke, encephalopathy)
    MAX(CASE 
      WHEN (diag.icd_version = 9 AND (diag.icd_code BETWEEN '430' AND '434' OR diag.icd_code BETWEEN '436' AND '437' OR diag.icd_code = '3483')) 
      OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I6%' OR diag.icd_code IN ('G9340','G9349'))) 
      THEN 1 ELSE 0 END) AS neurologic_comp
  FROM quintiles q
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON q.subject_id = diag.subject_id AND q.hadm_id = diag.hadm_id
  GROUP BY q.subject_id, q.hadm_id
),
final_cohort AS (
  SELECT 
    q.*,
    comp.cardiovascular_comp,
    comp.neurologic_comp,
    -- 30-day mortality (in-hospital or post-discharge)
    CASE 
      WHEN (q.deathtime IS NOT NULL AND DATETIME_DIFF(q.deathtime, q.admittime, DAY) <= 30)
        OR (q.deathtime IS NULL AND q.dod IS NOT NULL AND DATE_DIFF(DATE(q.dod), DATE(q.admittime), DAY) <= 30)
      THEN 1 ELSE 0 END AS mortality_30day,
    -- LOS for survivors (in days)
    CASE WHEN q.hospital_expire_flag = 0 THEN DATETIME_DIFF(q.dischtime, q.admittime, DAY) END AS los_survivors
  FROM quintiles q
  LEFT JOIN complications comp
    ON q.subject_id = comp.subject_id AND q.hadm_id = comp.hadm_id
)
SELECT 
  risk_quintile,
  COUNT(*) AS num_patients,
  AVG(mortality_30day) * 100 AS mortality_30day_rate,
  AVG(cardiovascular_comp) * 100 AS cardiovascular_complication_rate,
  AVG(neurologic_comp) * 100 AS neurologic_complication_rate,
  APPROX_QUANTILES(los_survivors, 100)[OFFSET(50)] AS median_los_survivors
FROM final_cohort
GROUP BY risk_quintile
ORDER BY risk_quintile;