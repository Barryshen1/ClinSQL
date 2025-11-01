WITH troponin_items AS (
  -- Identify hs-Troponin T related lab itemids by label heuristics
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
     OR LOWER(label) LIKE '%hs troponin%'
     OR LOWER(label) LIKE '%high sensitivity troponin%'
     OR LOWER(label) LIKE '%troponin, high sensitivity%'
),
troponin_events AS (
  -- All numeric troponin measurements (no time restriction yet)
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items ti USING(itemid)
  WHERE le.valuenum IS NOT NULL
),
-- Compute dataset-wide 99th percentile from available troponin events
p99 AS (
  SELECT
    APPROX_QUANTILES(valuenum, 100)[OFFSET(99)] AS p99_value
  FROM troponin_events
),
-- First hs-TnT measurement during each admission (restrict events to within admission timeframe)
first_tn AS (
  SELECT
    te.subject_id,
    te.hadm_id,
    te.valuenum AS first_tn,
    te.charttime
  FROM (
    SELECT
      te.*,
      ROW_NUMBER() OVER (PARTITION BY te.hadm_id ORDER BY te.charttime ASC, te.valuenum ASC) AS rn
    FROM troponin_events te
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON te.hadm_id = a.hadm_id
    WHERE te.charttime BETWEEN a.admittime AND a.dischtime
  ) te
  WHERE rn = 1
),
-- Admissions for male patients age 64-74 with primary diagnosis containing "chest pain"
cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    USING(subject_id, hadm_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND d.seq_num = 1  -- primary diagnosis
    AND LOWER(dd.long_title) LIKE '%chest pain%'
),
-- Eligible admissions: in cohort, have a first hs-TnT and that first value exceeds the 99th percentile
eligible AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    ca.anchor_age,
    ca.hospital_expire_flag,
    ft.first_tn
  FROM cohort_admissions ca
  JOIN first_tn ft
    USING(hadm_id)
  CROSS JOIN p99
  WHERE ft.first_tn > p99.p99_value
)
SELECT
  COUNT(*) AS n_admissions,
  ROUND(AVG(anchor_age), 2) AS mean_age,
  -- median age (approx)
  (SELECT APPROX_QUANTILES(anchor_age, 100)[OFFSET(50)] FROM eligible) AS median_age,
  -- First hs-TnT summary (count equals n_admissions)
  COUNT(first_tn) AS n_with_first_tn,
  ROUND(AVG(first_tn), 4) AS mean_first_tn,
  (SELECT APPROX_QUANTILES(first_tn, 100)[OFFSET(50)] FROM eligible) AS median_first_tn,
  ROUND(STDDEV_POP(first_tn), 4) AS sd_first_tn,
  (SELECT APPROX_QUANTILES(first_tn, 100)[OFFSET(25)] FROM eligible) AS first_tn_p25,
  (SELECT APPROX_QUANTILES(first_tn, 100)[OFFSET(75)] FROM eligible) AS first_tn_p75,
  MIN(first_tn) AS first_tn_min,
  MAX(first_tn) AS first_tn_max,
  -- In-hospital mortality
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths_in_hospital,
  CASE WHEN COUNT(*) = 0 THEN NULL
       ELSE ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2)
  END AS in_hospital_mortality_percent,
  -- Report the 99th percentile value used
  (SELECT p99_value FROM p99) AS hsTnT_p99_threshold
FROM eligible;