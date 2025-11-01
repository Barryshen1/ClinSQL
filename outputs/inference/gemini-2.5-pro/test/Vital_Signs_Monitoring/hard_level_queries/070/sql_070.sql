with a diagnosis of
-- Hyperosmolar Hyperglycemic State (HHS). For this cohort, it calculates an instability score
-- based on the sum of coefficients of variation (CV) for heart rate, respiratory rate, and
-- mean arterial pressure during the first 24 hours of their ICU stay.
-- The query then reports on the top quartile of patients by this instability score,
-- showing their specific score, decile, count of abnormal vital signs, ICU length of stay,
-- and in-hospital mortality.
-- Databases: physionet-data.mimiciv_3_1_hosp, physionet-data.mimiciv_3_1_icu

WITH
  -- Step 1: Identify the cohort of male ICU patients aged 78-88 with HHS.
  cohort AS (
    SELECT DISTINCT
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      i.los AS icu_los,
      a.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS i
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON i.hadm_id = a.hadm_id
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON i.subject_id = p.subject_id
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx ON i.hadm_id = dx.hadm_id
    WHERE
      -- Male patients
      p.gender = 'M'
      -- Aged 78-88 at the time of admission
      AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 78 AND 88
      -- Diagnosis of Hyperosmolar Hyperglycemic State (HHS)
      AND (
        (dx.icd_version = 9 AND dx.icd_code LIKE '2502%') -- Diabetes with hyperosmolarity
        OR (
          dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 4) IN (
            'E100',  -- Type 1 DM with hyperosmolarity
            'E110',  -- Type 2 DM with hyperosmolarity
            'E120',  -- Malnutrition-related DM with hyperosmolarity
            'E130',  -- Other specified DM with hyperosmolarity
            'E140'   -- Unspecified DM with hyperosmolarity
          )
        )
      )
  ),

  -- Step 2: Extract relevant vital signs from the first 24 hours of the ICU stay.
  vitals_first_24h AS (
    SELECT
      c.stay_id,
      ce.itemid,
      ce.valuenum
    FROM
      cohort AS c
      INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce ON c.stay_id = ce.stay_id
    WHERE
      -- Vitals within the first 24 hours of ICU admission
      ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
      -- Filter for Heart Rate, Respiratory Rate, and Mean Arterial Pressure itemids
      AND ce.itemid IN (
        220045,  -- Heart Rate
        220210,  -- Respiratory Rate
        220052,  -- Arterial Blood Pressure mean
        220181,  -- Non Invasive Blood Pressure mean
        225312   -- ART BP mean
      )
      AND ce.valuenum IS NOT NULL AND ce.valuenum > 0  -- Basic data cleaning
  ),

  -- Step 3: Calculate CV for each vital, and count abnormal measurements per stay.
  stay_stats AS (
    SELECT
      stay_id,
      -- Coefficient of Variation (CV) for Heart Rate
      SAFE_DIVIDE(STDDEV(IF(itemid = 220045, valuenum, NULL)), AVG(IF(itemid = 220045, valuenum, NULL))) * 100 AS hr_cv,
      -- CV for Respiratory Rate
      SAFE_DIVIDE(STDDEV(IF(itemid = 220210, valuenum, NULL)), AVG(IF(itemid = 220210, valuenum, NULL))) * 100 AS rr_cv,
      -- CV for Mean Arterial Pressure
      SAFE_DIVIDE(STDDEV(IF(itemid IN (220052, 220181, 225312), valuenum, NULL)), AVG(IF(itemid IN (220052, 220181, 225312), valuenum, NULL))) * 100 AS map_cv,
      -- Count of abnormal vital signs
      COUNTIF(
        (itemid = 220045 AND (valuenum < 60 OR valuenum > 100))  -- Abnormal HR
        OR (itemid = 220210 AND (valuenum < 12 OR valuenum > 20))  -- Abnormal RR
        OR (itemid IN (220052, 220181, 225312) AND valuenum < 65)  -- Abnormal MAP
      ) AS abnormal_vital_count
    FROM
      vitals_first_24h
    GROUP BY
      stay_id
  ),

  -- Step 4: Combine stats, calculate total instability score, and rank patients.
  ranked_stays AS (
    SELECT
      c.stay_id,
      c.icu_los,
      c.hospital_expire_flag AS in_hospital_mortality,
      s.abnormal_vital_count,
      -- Sum of CVs, replacing NULLs with 0 if a vital was not measured
      (COALESCE(s.hr_cv, 0) + COALESCE(s.rr_cv, 0) + COALESCE(s.map_cv, 0)) AS stay_instability_score,
      -- Rank into quartiles and deciles based on the instability score
      NTILE(4) OVER (ORDER BY (COALESCE(s.hr_cv, 0) + COALESCE(s.rr_cv, 0) + COALESCE(s.map_cv, 0)) DESC) AS quartile,
      NTILE(10) OVER (ORDER BY (COALESCE(s.hr_cv, 0) + COALESCE(s.rr_cv, 0) + COALESCE(s.map_cv, 0)) DESC) AS decile
    FROM
      cohort AS c
      INNER JOIN stay_stats AS s ON c.stay_id = s.stay_id
  )

-- Final Step: Report on the top quartile of patients.
SELECT
  stay_instability_score,
  decile,
  abnormal_vital_count,
  icu_los,
  in_hospital_mortality
FROM
  ranked_stays
WHERE
  quartile = 1
ORDER BY
  stay_instability_score DESC;