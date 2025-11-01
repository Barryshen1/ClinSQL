WITH cohort AS (
  -- male patients age 51-61 with both diabetes and acute heart failure
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.hospital_expire_flag = 0
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%acute heart failure%'
    )
),
prescriptions_windowed AS (
  -- pull prescriptions in each window and flag regimen components
  SELECT
    c.hadm_id,
    CASE
      WHEN p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
        THEN 'first24h'
      WHEN p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime
        THEN 'last12h'
    END AS time_window,
    MAX(CASE WHEN LOWER(p.drug) LIKE '%glargine%'
               OR LOWER(p.drug) LIKE '%detemir%'
               OR LOWER(p.drug) LIKE '%degludec%' THEN 1 ELSE 0 END) AS has_basal,
    MAX(CASE WHEN LOWER(p.drug) LIKE '%lispro%'
               OR LOWER(p.drug) LIKE '%aspart%'
               OR LOWER(p.drug) LIKE '%regular%' THEN 1 ELSE 0 END) AS has_bolus,
    MAX(CASE WHEN LOWER(p.drug) LIKE '%sliding%'
               OR LOWER(p.drug) LIKE '%ssi%' THEN 1 ELSE 0 END) AS has_sliding
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE (p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR))
     OR (p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime)
  GROUP BY c.hadm_id, time_window
),
regimen_classified AS (
  -- classify each hadm/window into one regimen category
  SELECT
    hadm_id,
    time_window,
    CASE
      WHEN has_basal = 1 AND has_bolus = 1 THEN 'Basal-Bolus'
      WHEN has_basal = 1 AND has_bolus = 0 THEN 'Basal'
      WHEN has_basal = 0 AND has_bolus = 1 THEN 'Bolus'
      WHEN has_sliding = 1 AND has_basal = 0 AND has_bolus = 0 THEN 'Sliding-Scale'
      ELSE 'Other'
    END AS regimen
  FROM prescriptions_windowed
),
counts AS (
  -- count patients per regimen and window
  SELECT
    time_window,
    regimen,
    COUNT(DISTINCT hadm_id) AS n_patients
  FROM regimen_classified
  WHERE regimen IN ('Basal-Bolus','Basal','Bolus','Sliding-Scale')
  GROUP BY time_window, regimen
),
totals AS (
  -- total unique admissions in cohort
  SELECT COUNT(DISTINCT hadm_id) AS total_cohort
  FROM cohort
)
SELECT
  c.time_window,
  c.regimen,
  c.n_patients,
  ROUND(100.0 * c.n_patients / t.total_cohort, 1) AS pct
FROM counts c
CROSS JOIN totals t
ORDER BY
  c.regimen,
  CASE c.time_window WHEN 'first24h' THEN 1 WHEN 'last12h' THEN 2 END;