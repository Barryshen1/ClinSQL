WITH ComorbidityScore AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_version = 9
    AND icd_code NOT IN ('V', 'Z', 'E', '99') -- Exclude non-disease codes
  GROUP BY
    subject_id,
    hadm_id
), ComorbidityPercentile AS (
  SELECT
    subject_id,
    hadm_id,
    comorbidity_count,
    PERCENTILE_CONT(comorbidity_count, 0.75) OVER (PARTITION BY subject_id) AS percentile_75
  FROM ComorbidityScore
), DVT_Patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    cp.comorbidity_count,
    cp.percentile_75
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN ComorbidityPercentile AS cp
    ON p.subject_id = cp.subject_id
    AND a.hadm_id = cp.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND cp.comorbidity_count >= cp.percentile_75
    AND a.hospital_expire_flag = 0 -- Only consider patients who died during the admission
), DVT_Diagnosis AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%deep vein thrombosis%'
    OR di.long_title LIKE '%DVT%'
), MajorComplication AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT icd_code) AS complication_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_version = 9
    AND icd_code IN ('410', '411', '414', '427', '428', '431', '433', '434', '435', '436', '437', '438', '439', '440', '441', '443', '446', '447', -- Missing closing parenthesis;