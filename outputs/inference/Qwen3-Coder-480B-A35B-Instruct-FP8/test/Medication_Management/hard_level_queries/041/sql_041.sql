WITH hf_admissions AS (
  -- Identify admissions with primary HF diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    d.seq_num = 1 -- primary diagnosis
    AND LOWER(dd.long_title) LIKE '%heart failure%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),

med_complexity AS (
  -- Compute 7-day medication complexity score
  SELECT
    e.hadm_id,
    COUNT(DISTINCT e.medication) AS med_complexity_score
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN hf_admissions h
    ON e.hadm_id = h.hadm_id
  WHERE
    e.charttime >= h.admittime
    AND e.charttime <= DATETIME_ADD(h.admittime, INTERVAL 7 DAY)
  GROUP BY e.hadm_id
),

admission_metrics AS (
  -- Add LOS, mortality, and next admission time
  SELECT
    h.hadm_id,
    h.hospital_expire_flag,
    DATE_DIFF(h.dischtime, h.admittime, DAY) AS los_days,
    COALESCE(LEAD(h.admittime) OVER (
      PARTITION BY h.subject_id ORDER BY h.admittime
    ), DATETIME('9999-12-31')) AS next_admittime,
    h.dischtime
  FROM hf_admissions h
),

readmission_flag AS (
  -- Flag 30-day readmission
  SELECT
    a.hadm_id,
    a.los_days,
    a.hospital_expire_flag,
    CASE
      WHEN DATETIME_DIFF(a.next_admittime, a.dischtime, DAY) <= 30 THEN 1
      ELSE 0
    END AS readmit_30_days
  FROM admission_metrics a
),

combined_data AS (
  -- Combine medication complexity with outcomes
  SELECT
    c.hadm_id,
    c.los_days,
    c.hospital_expire_flag,
    c.readmit_30_days,
    COALESCE(m.med_complexity_score, 0) AS med_complexity_score
  FROM readmission_flag c
  LEFT JOIN med_complexity m
    ON c.hadm_id = m.hadm_id
),

quintiles AS (
  -- Stratify into quintiles
  SELECT
    *,
    NTILE(5) OVER (ORDER BY med_complexity_score) AS score_quintile
  FROM combined_data
)

-- Final aggregation by quintile
SELECT
  score_quintile,
  COUNT(*) AS patient_count,
  MIN(med_complexity_score) AS min_score,
  MAX(med_complexity_score) AS max_score,
  AVG(los_days) AS mean_los_days,
  AVG(hospital_expire_flag) AS in_hosp_mortality_rate,
  AVG(readmit_30_days) AS readmit_30_day_rate
FROM quintiles
GROUP BY score_quintile
ORDER BY score_quintile;