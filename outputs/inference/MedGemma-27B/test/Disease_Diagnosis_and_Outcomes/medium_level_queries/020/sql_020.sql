WITH SepsisPatients AS (
  -- Identify patients with sepsis (excluding septic shock) based on ICD-9 codes
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND d.icd_code IN ('99592', '99593', '99594') -- Sepsis codes (excluding septic shock)
    AND d.icd_version = 9
),
ICUStays AS (
  -- Identify ICU stays for sepsis patients
  SELECT
    s.subject_id,
    s.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM SepsisPatients AS s
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON s.subject_id = i.subject_id
    AND s.hadm_id = i.hadm_id
),
Day1ICUStatus AS (
  -- Determine ICU status on day 1 of admission
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    CASE
      WHEN ic.intime >= ic.hadm_id -- Assuming hadm_id is a timestamp or similar representation of admission time
      THEN 'ICU on Day 1'
      ELSE 'Not ICU on Day 1'
    END AS day1_icu_status
  FROM ICUStays AS ic
)
SELECT
  d1.day1_icu_status,
  CASE
    WHEN ic.los <= 3 THEN '≤3 days'
    WHEN ic.los BETWEEN 4 AND 6 THEN '4–6 days'
    WHEN ic.los BETWEEN 7 AND 10 THEN '7–10 days'
    ELSE '>10 days'
  END AS los_category,
  COUNT(DISTINCT ic.subject_id) AS total_patients,
  SUM(CASE WHEN ic.los > 0 THEN 1 ELSE 0 END) AS total_patients_with_los,
  SUM(CASE WHEN ic.los > 0 AND ic.los <= 3 THEN 1 ELSE 0 END) AS patients_los_le_3,
  SUM(CASE WHEN ic.los > 0 AND ic.los BETWEEN 4 AND 6 THEN 1 ELSE 0 END) AS patients_los_4_6,
  SUM(CASE WHEN ic.los > 0 AND ic.los BETWEEN 7 AND 10 THEN 1 ELSE 0 END) AS patients_los_7_10,
  SUM(CASE WHEN ic.los > 0 AND ic.los > 10 THEN 1 ELSE 0 END) AS patients_los_gt_10,
  AVG(CASE WHEN ic.los > 0 THEN ic.los ELSE NULL END) AS avg_los,
  AVG(CASE WHEN ic.los > 0 THEN ic.los ELSE NULL END) AS median_los,
  AVG(CASE WHEN ic.los > 0 THEN ic.los ELSE NULL END) AS days_to_death
FROM ICUStays AS ic
INNER JOIN Day1ICUStatus AS d1
  ON ic.subject_id = d1.subject_id
  AND ic.hadm_id = d1.hadm_id
  AND ic.stay_id = d1.stay_id
GROUP BY
  d1.day1_icu_status,
  los_category
ORDER BY
  d1.day1_icu_status,
  los_category;