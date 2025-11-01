WITH sepsis_cohort AS (
  -- Base cohort: male, 78-88, ICU stays with primary sepsis diagnosis
  SELECT 
    i.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    i.outtime,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    a.dischtime,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id, i.hadm_id ORDER BY i.intime) AS rn  -- First ICU stay per admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = i.subject_id 
        AND d.hadm_id = i.hadm_id 
        AND d.seq_num = 1 
        AND d.icd_version = '10'
        AND (
          d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%' OR  -- Streptococcal/Other sepsis
          d.icd_code LIKE 'R65%' OR  -- SIRS/Sepsis
          d.icd_code IN ('R572', 'T814', 'T81.4')  -- Septic shock, infection complications
        )
    )
    AND i.los > 0
),

vital_instability AS (
  -- Compute instability score: binary flags for key vitals in first 24h
  SELECT 
    sc.stay_id,
    -- HR instability
    MAX(CASE WHEN hr.itemid IS NOT NULL AND c.valuenum > 140 OR c.valuenum < 50 THEN 1 ELSE 0 END) AS hr_flag,
    -- SBP
    MAX(CASE WHEN sbp.itemid IS NOT NULL AND c.valuenum < 90 THEN 1 ELSE 0 END) AS sbp_flag,
    -- RR
    MAX(CASE WHEN rr.itemid IS NOT NULL AND (c.valuenum > 35 OR c.valuenum < 8) THEN 1 ELSE 0 END) AS rr_flag,
    -- Temp (convert to C for consistency)
    MAX(CASE WHEN temp.itemid IS NOT NULL 
             AND (CASE WHEN c.valueuom = 'F' THEN (c.valuenum - 32) * 5/9 ELSE c.valuenum END) > 39 
                  OR (CASE WHEN c.valueuom = 'F' THEN (c.valuenum - 32) * 5/9 ELSE c.valuenum END) < 35 
             THEN 1 ELSE 0 END) AS temp_flag,
    -- SpO2
    MAX(CASE WHEN spo2.itemid IS NOT NULL AND c.valuenum < 90 THEN 1 ELSE 0 END) AS spo2_flag
  FROM sepsis_cohort sc
  -- Pre-filter chartevents for first 24h
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON c.stay_id = sc.stay_id
    AND c.charttime >= sc.intime 
    AND c.charttime < TIMESTAMP_ADD(sc.intime, INTERVAL 1 DAY)
    AND c.valuenum IS NOT NULL
    AND c.itemid IS NOT NULL
  -- Join d_items separately for each vital to avoid label type issues
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` hr
    ON c.itemid = hr.itemid AND hr.label IN ('Heart Rate', 'HR') AND hr.category = 'Vital Signs'
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` sbp
    ON c.itemid = sbp.itemid AND sbp.label IN ('Systolic blood pressure', 'SBP') AND sbp.category = 'Vital Signs'
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` rr
    ON c.itemid = rr.itemid AND rr.label IN ('Respiratory rate', 'RespRate') AND rr.category = 'Vital Signs'
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` temp
    ON c.itemid = temp.itemid AND temp.label IN ('Temperature Celsius', 'Temperature Fahrenheit') AND temp.category = 'Vital Signs'
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` spo2
    ON c.itemid = spo2.itemid AND spo2.label = 'SpO2' AND spo2.category = 'Vital Signs'
  WHERE sc.rn = 1  -- First stay only
  GROUP BY sc.stay_id
),

scored_cohort AS (
  SELECT 
    sc.stay_id,
    sc.los,
    sc.hospital_expire_flag,
    COALESCE(vi.hr_flag, 0) + COALESCE(vi.sbp_flag, 0) + COALESCE(vi.rr_flag, 0) + 
    COALESCE(vi.temp_flag, 0) + COALESCE(vi.spo2_flag, 0) AS raw_score,
    -- Scale to 0-100 (max 5 * 20 = 100)
    (COALESCE(vi.hr_flag, 0) + COALESCE(vi.sbp_flag, 0) + COALESCE(vi.rr_flag, 0) + 
     COALESCE(vi.temp_flag, 0) + COALESCE(vi.spo2_flag, 0)) * 20 AS instability_score
  FROM sepsis_cohort sc
  LEFT JOIN vital_instability vi
    ON sc.stay_id = vi.stay_id
  WHERE sc.rn = 1  -- First stay only
)

-- Percentile rank for score=85 (over entire cohort)
SELECT 
  'Percentile for instability score 85' AS metric,
  CASE 
    WHEN COUNTIF(instability_score = 85) > 0 
    THEN ROUND(PERCENT_RANK() OVER (ORDER BY instability_score) * 100, 2) 
    ELSE NULL 
  END AS percentile
FROM scored_cohort
WHERE instability_score = 85

UNION ALL

-- Mean ICU LOS for Q4 (highest scores)
SELECT 
  'Q4 Mean ICU LOS' AS metric,
  ROUND(AVG(los), 2) AS value
FROM (
  SELECT 
    los,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS score_quartile
  FROM scored_cohort
) q
WHERE score_quartile = 1  -- Top quartile (highest instability)

UNION ALL

-- Hospital mortality for Q4
SELECT 
  'Q4 Hospital Mortality Rate (%)' AS metric,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT)) * 100, 2) AS value
FROM (
  SELECT 
    hospital_expire_flag,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS score_quartile
  FROM scored_cohort
) q
WHERE score_quartile = 1;