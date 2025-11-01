WITH
-- Get male patients aged 43-53
eligible_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 43 AND 53
),

-- Get their admissions with transplant diagnoses
transplant_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    d.icd_code,
    d.long_title AS diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  JOIN
    eligible_patients p
    ON a.subject_id = p.subject_id
  WHERE
    d.long_title LIKE '%transplant%'
    OR d.icd_code IN (
      'V42.0', 'V42.1', 'V42.2', 'V42.3', 'V42.4', 'V42.5', 'V42.6', 'V42.7', 'V42.8', 'V42.9',
      'Z94.0', 'Z94.1', 'Z94.2', 'Z94.3', 'Z94.4', 'Z94.5', 'Z94.6', 'Z94.7', 'Z94.8', 'Z94.9'
    )
),

-- Calculate medication complexity score for first 7 days
medication_complexity AS (
  SELECT
    ta.subject_id,
    ta.hadm_id,
    -- Count distinct medications
    COUNT(DISTINCT ph.medication) AS distinct_med_count,
    -- Count total medication orders
    COUNT(ph.pharmacy_id) AS total_med_orders,
    -- Count distinct routes
    COUNT(DISTINCT ph.route) AS distinct_route_count,
    -- Count distinct frequencies
    COUNT(DISTINCT ph.frequency) AS distinct_frequency_count,
    -- Calculate complexity score (weighted sum)
    (COUNT(DISTINCT ph.medication) * 2 +
     COUNT(DISTINCT ph.route) * 1.5 +
     COUNT(DISTINCT ph.frequency) * 1 +
     COUNT(ph.pharmacy_id) * 0.5) AS complexity_score
  FROM
    transplant_admissions ta
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ta.hadm_id = ph.hadm_id
    AND ph.starttime BETWEEN ta.admittime AND TIMESTAMP_ADD(ta.admittime, INTERVAL 7 DAY)
  GROUP BY
    ta.subject_id, ta.hadm_id
),

-- Calculate quartiles for complexity scores
quartiles AS (
  SELECT
    complexity_score,
    NTILE(4) OVER (ORDER BY complexity_score) AS quartile
  FROM
    medication_complexity
  WHERE
    complexity_score > 0
),

-- Get LOS and readmission info
outcomes AS (
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.complexity_score,
    q.quartile,
    -- Length of stay in days
    TIMESTAMP_DIFF(ta.dischtime, ta.admittime, DAY) AS los,
    -- In-hospital mortality
    ta.hospital_expire_flag,
    -- Check for 30-day readmission
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ta.subject_id
      AND a2.hadm_id > ta.hadm_id
      AND a2.admittime BETWEEN ta.dischtime AND TIMESTAMP_ADD(ta.dischtime, INTERVAL 30 DAY)
    ) AS readmitted_30d
  FROM
    medication_complexity mc
  JOIN
    transplant_admissions ta
    ON mc.hadm_id = ta.hadm_id
  JOIN
    quartiles q
    ON mc.complexity_score = q.complexity_score
)

-- Final aggregated results by quartile
SELECT
  quartile,
  COUNT(*) AS n,
  ROUND(AVG(complexity_score), 2) AS mean_complexity_score,
  ROUND(AVG(los), 2) AS mean_los,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS mortality_rate,
  ROUND(SUM(CASE WHEN readmitted_30d THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS readmission_rate_30d
FROM
  outcomes
GROUP BY
  quartile
ORDER BY
  quartile;