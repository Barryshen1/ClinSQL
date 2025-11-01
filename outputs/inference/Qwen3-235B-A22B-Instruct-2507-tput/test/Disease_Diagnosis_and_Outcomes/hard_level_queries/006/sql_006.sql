WITH age_filtered AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.dod,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 70 AND 80
),

-- Filter for lower GI bleeding diagnosis codes
lgib_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE LOWER(long_title) LIKE '%lower gastrointestinal tract bleed%'
     OR LOWER(long_title) LIKE '%lower gi bleed%'
     OR LOWER(long_title) LIKE '%diverticulosis with hemorrhage%'
     OR LOWER(long_title) LIKE '%hemorrhage of rectum%'
     OR LOWER(long_title) LIKE '%bleeding%diverticulosis%'
     OR LOWER(long_title) LIKE '%angiodysplasia%'
     OR LOWER(long_title) LIKE '%colonic bleed%'
),

admissions_lgib AS (
  SELECT DISTINCT af.*
  FROM age_filtered af
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON af.hadm_id = di.hadm_id
  INNER JOIN lgib_codes lgc
    ON di.icd_code = lgc.icd_code
),

-- ICU admission flag
icu_adm AS (
  SELECT DISTINCT hadm_id, 1 AS had_icu
  FROM `physionet-data.mimiciv_3_1_icu`.icustays
),

-- Transfusion: RBC in prescriptions
transfusion AS (
  SELECT DISTINCT hadm_id, 1 AS had_transfusion
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions
  WHERE LOWER(drug) LIKE '%red blood cell%'
    AND LOWER(drug) NOT LIKE '%plasma%'
    AND LOWER(drug) NOT LIKE '%platelet%'
    AND LOWER(drug) NOT LIKE '%iv fluid%'
),

-- Surgery: major GI surgery codes
surg_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures
  WHERE LOWER(long_title) LIKE '%colectomy%'
     OR LOWER(long_title) LIKE '%resection of colon%'
     OR LOWER(long_title) LIKE '%proctectomy%'
     OR LOWER(long_title) LIKE '%enterectomy%'
     OR LOWER(long_title) LIKE '%resection of intestine%'
),

surgery AS (
  SELECT DISTINCT al.hadm_id, 1 AS had_surgery
  FROM admissions_lgib al
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.procedures_icd pi
    ON al.hadm_id = pi.hadm_id
  INNER JOIN surg_codes sc
    ON pi.icd_code = sc.icd_code
),

-- Combine all complications and compute score
complications AS (
  SELECT
    al.*,
    COALESCE(icu.had_icu, 0) AS had_icu,
    COALESCE(tx.had_transfusion, 0) AS had_transfusion,
    COALESCE(sx.had_surgery, 0) AS had_surgery,
    al.hospital_expire_flag AS had_death
  FROM admissions_lgib al
  LEFT JOIN icu_adm icu ON al.hadm_id = icu.hadm_id
  LEFT JOIN transfusion tx ON al.hadm_id = tx.hadm_id
  LEFT JOIN surgery sx ON al.hadm_id = sx.hadm_id
),

scored AS (
  SELECT
    *,
    (had_icu + had_transfusion + had_surgery + had_death) AS complication_score
  FROM complications
),

quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY complication_score) AS risk_quintile
  FROM scored
),

outcomes AS (
  SELECT
    risk_quintile,
    COUNT(*) AS N,
    AVG(CASE WHEN dod IS NOT NULL AND dod <= DATETIME_ADD(admittime, INTERVAL 90 DAY) THEN 1.0 ELSE 0.0 END) AS mortality_90d_rate,
    AVG(CASE WHEN complication_score > 0 THEN 1.0 ELSE 0.0 END) AS major_complication_rate,
    APPROX_QUANTILES(
      CASE WHEN (dod IS NULL OR dod > DATETIME_ADD(admittime, INTERVAL 90 DAY))
           THEN DATETIME_DIFF(dischtime, admittime, SECOND) / 86400.0 END, 100
    )[OFFSET(50)] AS median_los_survivors
  FROM quintiles
  GROUP BY risk_quintile
)

SELECT
  risk_quintile,
  N,
  mortality_90d_rate,
  major_complication_rate,
  median_los_survivors
FROM outcomes
ORDER BY risk_quintile;