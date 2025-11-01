WITH cohort AS (
  -- Step 1: Get male patients aged 58-68
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
),
dx_chestpain_ami AS (
  -- Step 2: Admissions with chest pain or AMI diagnosis
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (
      -- Chest pain ICD-10 codes
      dd.icd_code IN ('R079', 'R072', 'R071', 'R0789')
      OR dd.long_title LIKE '%chest pain%'
      -- AMI ICD-10/ICD-9 codes
      OR dd.icd_code LIKE 'I21%' OR dd.icd_code LIKE 'I22%'
      OR dd.icd_code LIKE '410%'
      OR dd.long_title LIKE '%acute myocardial infarction%'
    )
),
troponin_t_first AS (
  -- Step 3: Get initial Troponin T >0.04 ng/mL per admission
  SELECT
    l.subject_id,
    l.hadm_id,
    MIN(l.charttime) AS first_charttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
      ON l.itemid = dl.itemid
  WHERE
    LOWER(dl.label) LIKE '%troponin t%'
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/mL'
  GROUP BY
    l.subject_id, l.hadm_id
),
troponin_t_value AS (
  -- Get the value for the first Troponin T per admission
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS initial_troponin_t
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN troponin_t_first tf
      ON l.subject_id = tf.subject_id
      AND l.hadm_id = tf.hadm_id
      AND l.charttime = tf.first_charttime
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
      ON l.itemid = dl.itemid
  WHERE
    LOWER(dl.label) LIKE '%troponin t%'
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/mL'
),
final_cohort AS (
  -- Step 4: Combine all filters
  SELECT
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    t.initial_troponin_t,
    c.hospital_expire_flag
  FROM
    cohort c
    INNER JOIN dx_chestpain_ami dx
      ON c.subject_id = dx.subject_id AND c.hadm_id = dx.hadm_id
    INNER JOIN troponin_t_value t
      ON c.subject_id = t.subject_id AND c.hadm_id = t.hadm_id
  WHERE
    t.initial_troponin_t > 0.04
)
-- Step 5: Summary statistics
SELECT
  COUNT(*) AS num_admissions,
  ROUND(AVG(anchor_age), 2) AS mean_age,
  APPROX_QUANTILES(anchor_age, 2)[OFFSET(1)] AS median_age,
  ROUND(AVG(initial_troponin_t), 3) AS mean_initial_troponin_t,
  APPROX_QUANTILES(initial_troponin_t, 2)[OFFSET(1)] AS median_initial_troponin_t,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 4) AS in_hospital_mortality_rate
FROM
  final_cohort;