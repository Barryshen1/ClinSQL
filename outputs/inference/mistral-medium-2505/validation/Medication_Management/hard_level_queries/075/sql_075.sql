WITH
-- Step 1: Identify male patients aged 58-68 with COPD exacerbation
copd_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND di.icd_code IN ('J440', 'J441', 'J449') -- COPD exacerbation codes
    AND a.admission_type != 'NEWBORN' -- Exclude newborns
),

-- Step 2: Calculate medication complexity in first 72 hours
med_complexity AS (
  SELECT
    ph.subject_id,
    ph.hadm_id,
    COUNT(DISTINCT medication) AS distinct_med_count,
    COUNT(DISTINCT route) AS distinct_route_count,
    COUNT(DISTINCT frequency) AS distinct_frequency_count,
    COUNT(DISTINCT medication) + COUNT(DISTINCT route) + COUNT(DISTINCT frequency) AS complexity_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
  JOIN
    copd_patients c ON ph.subject_id = c.subject_id AND ph.hadm_id = c.hadm_id
  WHERE
    TIMESTAMP_DIFF(ph.starttime, c.admittime, HOUR) <= 72
  GROUP BY
    ph.subject_id, ph.hadm_id
),

-- Step 3: Assign tertiles based on complexity score
patient_tertile AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    m.complexity_score,
    NTILE(3) OVER (ORDER BY m.complexity_score) AS tertile
  FROM
    copd_patients c
  JOIN
    med_complexity m ON c.subject_id = m.subject_id AND c.hadm_id = m.hadm_id
),

-- Step 4: Calculate 30-day readmission
readmission_30d AS (
  SELECT
    pt.subject_id,
    pt.hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted_30d
  FROM
    patient_tertile pt
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a2 ON pt.subject_id = a2.subject_id
    AND a2.admittime > pt.dischtime
    AND a2.admittime <= TIMESTAMP_ADD(pt.dischtime, INTERVAL 30 DAY)
    AND pt.hadm_id != a2.hadm_id
)

-- Final aggregation by tertile
SELECT
  tertile,
  COUNT(*) AS n,
  MIN(complexity_score) AS min_complexity,
  MAX(complexity_score) AS max_complexity,
  ROUND(AVG(complexity_score), 2) AS mean_complexity,
  ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)), 2) AS mean_los,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_pct,
  ROUND(100 * SUM(readmitted_30d) / COUNT(*), 2) AS readmission_30d_pct
FROM
  patient_tertile pt
JOIN
  readmission_30d r ON pt.subject_id = r.subject_id AND pt.hadm_id = r.hadm_id
GROUP BY
  tertile
ORDER BY
  tertile;