WITH patients_filtered AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
),

sepsis_status AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    CASE
      WHEN di.long_title LIKE '%septic shock%' THEN 'septic_shock'
      WHEN di.long_title LIKE '%sepsis%' AND di.long_title NOT LIKE '%shock%' THEN 'sepsis_without_shock'
      ELSE NULL
    END AS sepsis_group
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code
  WHERE di.long_title LIKE '%sepsis%'
),

charlson AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    SUM(
      CASE
        WHEN di.long_title LIKE '%myocardial infarction%' THEN 1
        WHEN di.long_title LIKE '%congestive heart failure%' THEN 1
        WHEN di.long_title LIKE '%peripheral vascular disease%' THEN 1
        WHEN di.long_title LIKE '%cerebrovascular disease%' THEN 1
        WHEN di.long_title LIKE '%dementia%' THEN 1
        WHEN di.long_title LIKE '%chronic pulmonary disease%' THEN 1
        WHEN di.long_title LIKE '%connective tissue disease%' THEN 1
        WHEN di.long_title LIKE '%peptic ulcer disease%' THEN 1
        WHEN di.long_title LIKE '%mild liver disease%' THEN 1
        WHEN di.long_title LIKE '%diabetes without chronic complications%' THEN 1
        WHEN di.long_title LIKE '%diabetes with chronic complications%' THEN 2
        WHEN di.long_title LIKE '%hemiplegia%' OR di.long_title LIKE '%paraplegia%' THEN 2
        WHEN di.long_title LIKE '%renal disease%' THEN 2
        WHEN di.long_title LIKE '%malignancy%' AND di.long_title NOT LIKE '%metastatic%' THEN 2
        WHEN di.long_title LIKE '%moderate or severe liver disease%' THEN 3
        WHEN di.long_title LIKE '%metastatic solid tumor%' THEN 6
        WHEN di.long_title LIKE '%leukemia%' OR di.long_title LIKE '%lymphoma%' THEN 2
        ELSE 0
      END
    ) AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code
  GROUP BY d.subject_id, d.hadm_id
),

los_group AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN DATE_DIFF(dischtime, admittime, DAY) <= 7 THEN '<=7'
      ELSE '>7'
    END AS los_group
  FROM patients_filtered
),

charlson_group AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN charlson_score <= 3 THEN '<=3'
      WHEN charlson_score BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_group
  FROM charlson
),

mortality_data AS (
  SELECT
    l.los_group,
    c.charlson_group,
    s.sepsis_group,
    SUM(p.hospital_expire_flag) * 1.0 / COUNT(*) AS mortality_rate
  FROM patients_filtered p
  JOIN sepsis_status s ON p.subject_id = s.subject_id AND p.hadm_id = s.hadm_id
  JOIN los_group l ON p.subject_id = l.subject_id AND p.hadm_id = l.hadm_id
  JOIN charlson_group c ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id
  WHERE s.sepsis_group IS NOT NULL
  GROUP BY l.los_group, c.charlson_group, s.sepsis_group
)

SELECT
  los_group,
  charlson_group,
  MAX(CASE WHEN sepsis_group = 'sepsis_without_shock' THEN mortality_rate END) AS mortality_sepsis_without_shock,
  MAX(CASE WHEN sepsis_group = 'septic_shock' THEN mortality_rate END) AS mortality_septic_shock,
  (MAX(CASE WHEN sepsis_group = 'septic_shock' THEN mortality_rate END) - MAX(CASE WHEN sepsis_group = 'sepsis_without_shock' THEN mortality_rate END)) AS absolute_difference,
  (MAX(CASE WHEN sepsis_group = 'septic_shock' THEN mortality_rate END) - MAX(CASE WHEN sepsis_group = 'sepsis_without_shock' THEN mortality_rate END)) / NULLIF(MAX(CASE WHEN sepsis_group = 'sepsis_without_shock' THEN mortality_rate END), 0) AS relative_difference
FROM mortality_data
GROUP BY los_group, charlson_group;