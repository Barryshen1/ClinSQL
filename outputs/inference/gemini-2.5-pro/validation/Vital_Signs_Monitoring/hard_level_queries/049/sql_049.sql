WITH sepsis_stays AS (
  -- Step 1: Identify the cohort of ICU stays for male patients aged 78-88 with sepsis
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) BETWEEN 78 AND 88
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = adm.hadm_id
      AND (
        d.icd_code LIKE 'A41%'      -- Sepsis (ICD-10)
        OR d.icd_code LIKE 'R65.2%' -- Severe sepsis (ICD-10)
        OR d.icd_code IN ('99591', '99592', '78552') -- Sepsis, Severe Sepsis, Septic Shock (ICD-9)
      )
    )
),

instability_scores AS (
  -- Step 2: Calculate the instability score for each stay in the cohort
  -- Score is defined as the count of abnormal vital signs in the first 24 hours
  SELECT
    s.stay_id,
    s.hadm_id,
    s.subject_id,
    COUNT(ce.itemid) AS instability_score
  FROM sepsis_stays AS s
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON s.stay_id = ce.stay_id
    AND ce.charttime BETWEEN s.intime AND DATETIME_ADD(s.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND (
      -- Abnormal conditions for various vital signs
      (ce.itemid = 220045 AND (ce.valuenum > 100 OR ce.valuenum < 60))     -- Heart Rate
      OR (ce.itemid = 220179 AND ce.valuenum < 90)                        -- Non Invasive Blood Pressure systolic
      OR (ce.itemid = 220052 AND ce.valuenum < 65)                        -- Arterial Blood Pressure mean
      OR (ce.itemid = 220210 AND (ce.valuenum > 22 OR ce.valuenum < 10)) -- Respiratory Rate
      OR (ce.itemid = 223762 AND (ce.valuenum > 38.3 OR ce.valuenum < 36)) -- Temperature C
      OR (ce.itemid = 220277 AND ce.valuenum < 90)                        -- O2 saturation pulseoxymetry
      OR (ce.itemid = 226758 AND ce.valuenum < 15)                        -- GCS Total (Corrected itemid)
    )
  GROUP BY
    s.stay_id, s.hadm_id, s.subject_id
),

final_data AS (
  -- Step 3: Combine scores with outcomes and assign quartiles
  SELECT
    sc.instability_score,
    icu.los,
    adm.hospital_expire_flag,
    NTILE(4) OVER (ORDER BY sc.instability_score) AS score_quartile
  FROM instability_scores AS sc
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON sc.stay_id = icu.stay_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON sc.hadm_id = adm.hadm_id
)

-- Step 4: Calculate and present the final metrics
SELECT
  'Percentile rank of score 85' AS metric,
  (
    SELECT
        ROUND(
            SAFE_DIVIDE(
                CAST(COUNTIF(instability_score < 85) AS FLOAT64),
                (COUNT(instability_score) - 1)
            ) * 100
        , 2)
    FROM final_data
  ) AS value

UNION ALL

SELECT
  'Mean ICU LOS (days) for Q4' AS metric,
  ROUND(AVG(los), 2) AS value
FROM final_data
WHERE score_quartile = 4

UNION ALL

SELECT
  'Hospital mortality rate (%) for Q4' AS metric,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS value
FROM final_data
WHERE score_quartile = 4;