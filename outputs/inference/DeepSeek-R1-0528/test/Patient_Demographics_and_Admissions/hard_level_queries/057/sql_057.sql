WITH uti_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE REGEXP_CONTAINS(LOWER(long_title), r'urinary tract infection')
),
index_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  INNER JOIN (
    SELECT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    INNER JOIN uti_codes 
      ON diag.icd_code = uti_codes.icd_code 
      AND diag.icd_version = uti_codes.icd_version
    WHERE diag.seq_num = 1
  ) uti
    ON adm.hadm_id = uti.hadm_id
  WHERE
    p.gender = 'M'
    AND adm.insurance = 'Medicare'
    AND LOWER(adm.admission_location) LIKE '%emergency%'
),
first_index_adm AS (
  SELECT *
  FROM (
    SELECT 
      *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM index_admissions
    WHERE 
      age_at_admission BETWEEN 60 AND 70
      AND hospital_expire_flag = 0  -- Exclude in-hospital deaths
  )
  WHERE rn = 1  -- First qualifying admission per patient
),
cohort AS (
  SELECT 
    idx.*,
    CASE WHEN readm.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted
  FROM first_index_adm idx
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` readm
    ON idx.subject_id = readm.subject_id
    AND readm.admittime > idx.dischtime  -- Readmission after discharge
    AND readm.admittime <= DATE_ADD(idx.dischtime, INTERVAL 30 DAY)  -- Within 30 days
),
stats AS (
  SELECT
    readmitted,
    COUNT(*) AS n,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
    ROUND(COUNTIF(los_days > 9) * 100.0 / COUNT(*), 2) AS percent_los_gt9
  FROM cohort
  GROUP BY readmitted
),
overall AS (
  SELECT
    COUNT(*) AS total_index_admissions,
    COUNTIF(readmitted = 1) AS readmitted_count
  FROM cohort
)
SELECT
  total_index_admissions,
  readmitted_count,
  readmitted_count / total_index_admissions AS readmission_rate,
  (SELECT median_los FROM stats WHERE readmitted = 1) AS readmitted_median_los,
  (SELECT percent_los_gt9 FROM stats WHERE readmitted = 1) AS readmitted_percent_los_gt9,
  (SELECT median_los FROM stats WHERE readmitted = 0) AS non_readmitted_median_los,
  (SELECT percent_los_gt9 FROM stats WHERE readmitted = 0) AS non_readmitted_percent_los_gt9
FROM overall;