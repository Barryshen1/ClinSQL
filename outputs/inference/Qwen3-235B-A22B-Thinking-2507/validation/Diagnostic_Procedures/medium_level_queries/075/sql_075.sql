WITH acs_codes AS (
  SELECT 'I200' AS icd_code  -- Unstable angina
  UNION ALL SELECT 'I210'    -- ST elevation myocardial infarction
  UNION ALL SELECT 'I211'
  UNION ALL SELECT 'I212'
  UNION ALL SELECT 'I213'
  UNION ALL SELECT 'I214'    -- Non-ST elevation myocardial infarction
  UNION ALL SELECT 'I219'
  UNION ALL SELECT 'I220'    -- Subsequent ST elevation myocardial infarction
  UNION ALL SELECT 'I221'
  UNION ALL SELECT 'I222'
  UNION ALL SELECT 'I223'
  UNION ALL SELECT 'I224'
  UNION ALL SELECT 'I225'
  UNION ALL SELECT 'I226'
  UNION ALL SELECT 'I227'
  UNION ALL SELECT 'I228'
  UNION ALL SELECT 'I229'
  UNION ALL SELECT 'I240'    -- Other acute ischemic heart diseases
  UNION ALL SELECT 'I241'
  UNION ALL SELECT 'I248'
  UNION ALL SELECT 'I249'
),
cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    CASE 
      WHEN d1.hadm_id IS NOT NULL THEN 'primary'
      WHEN d2.hadm_id IS NOT NULL THEN 'secondary'
      ELSE NULL
    END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  -- Check if ACS is primary diagnosis (seq_num = 1)
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE seq_num = 1
      AND icd_code IN (SELECT icd_code FROM acs_codes)
  ) d1 ON a.hadm_id = d1.hadm_id
  -- Check if ACS is secondary diagnosis (seq_num > 1)
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE seq_num > 1
      AND icd_code IN (SELECT icd_code FROM acs_codes)
  ) d2 ON a.hadm_id = d2.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 59 AND 69
    AND (d1.hadm_id IS NOT NULL OR d2.hadm_id IS NOT NULL)
),
procedure_counts AS (
  SELECT 
    c.hadm_id,
    c.diagnosis_type,
    -- Count procedures in days 1-3 (24-72 hours after admission)
    COUNTIF(DATE_DIFF(h.chartdate, c.admittime, DAY) BETWEEN 1 AND 3) AS count_1_3,
    -- Count procedures in days 4-7 (96-168 hours after admission)
    COUNTIF(DATE_DIFF(h.chartdate, c.admittime, DAY) BETWEEN 4 AND 7) AS count_4_7
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h 
    ON c.hadm_id = h.hadm_id
    AND h.chartdate >= c.admittime
    AND (h.chartdate <= c.dischtime OR c.dischtime IS NULL)
  GROUP BY c.hadm_id, c.diagnosis_type
),
unpivoted AS (
  SELECT diagnosis_type, '1-3 days' AS time_period, count_1_3 AS procedure_count
  FROM procedure_counts
  WHERE count_1_3 > 0
  UNION ALL
  SELECT diagnosis_type, '4-7 days' AS time_period, count_4_7 AS procedure_count
  FROM procedure_counts
  WHERE count_4_7 > 0
)
SELECT
  diagnosis_type,
  time_period,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] AS p75,
  COUNT(*) AS num_admissions
FROM unpivoted
GROUP BY diagnosis_type, time_period
ORDER BY diagnosis_type, time_period;