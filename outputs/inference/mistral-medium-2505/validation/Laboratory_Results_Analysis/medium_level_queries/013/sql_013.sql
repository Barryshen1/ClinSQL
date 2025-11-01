WITH
-- Get male patients aged 50-60
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 50 AND 60
),

-- Get admissions with chest pain or AMI
chest_pain_ami_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM eligible_patients)
    AND (
      -- Chest pain ICD codes (example - adjust as needed)
      di.icd_code IN ('R07.9', 'R07.1', 'R07.2', 'I21.9', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4')
      -- Or use LIKE for broader matching if needed
      OR di.long_title LIKE '%chest pain%'
      OR di.long_title LIKE '%acute myocardial infarction%'
      OR di.long_title LIKE '%AMI%'
    )
),

-- Get first hs-TnT measurement per admission
first_hs_tnt AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON
    l.itemid = d.itemid
  JOIN
    chest_pain_ami_admissions cpa
  ON
    l.subject_id = cpa.subject_id AND l.hadm_id = cpa.hadm_id
  WHERE
    d.label = 'Troponin T, High Sensitivity'
    AND l.valuenum > 0.014  -- ULN for hs-TnT
  QUALIFY ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) = 1
),

-- Calculate percentiles
percentiles AS (
  SELECT
    PERCENTILE_DISC(valuenum, 0.5) OVER() AS median_hs_tnt,
    PERCENTILE_DISC(valuenum, 0.25) OVER() AS q1_hs_tnt,
    PERCENTILE_DISC(valuenum, 0.75) OVER() AS q3_hs_tnt
  FROM first_hs_tnt
  LIMIT 1
)

-- Final aggregation
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(valuenum) AS mean_hs_tnt,
  (SELECT median_hs_tnt FROM percentiles) AS median_hs_tnt,
  (SELECT q1_hs_tnt FROM percentiles) AS q1_hs_tnt,
  (SELECT q3_hs_tnt FROM percentiles) AS q3_hs_tnt,
  (SELECT q3_hs_tnt FROM percentiles) - (SELECT q1_hs_tnt FROM percentiles) AS iqr_hs_tnt
FROM
  first_hs_tnt;