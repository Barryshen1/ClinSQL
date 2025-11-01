WITH cohort AS (
  -- Septic shock cohort: Female, 89-99, with septic shock ICD
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    i.stay_id,
    i.intime,
    i.outtime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 89 AND 99
    AND (
      (d.icd_version = 9 AND d.icd_code = '785.52') 
      OR (d.icd_version = 10 AND d.icd_code = 'R65.21')
    )
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY i.intime) = 1  -- First ICU stay
),
general_cohort AS (
  -- General cohort: Female, 89-99, no septic shock
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    i.stay_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 89 AND 99
    AND a.hadm_id NOT IN (SELECT hadm_id FROM cohort)  -- Exclude septic shock
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY i.intime) = 1
),
-- SOFA Score Calculation (first 48 hours)
sofa_resp AS (
  -- Respiration: PaO2/FiO2 ratio
  SELECT 
    c.stay_id,
    MIN(
      CASE
        WHEN pao2 IS NULL THEN NULL
        WHEN vent = 1 OR pao2 < 100 THEN 4
        WHEN pao2 < 200 THEN 3
        WHEN pao2 < 300 THEN 2
        WHEN pao2 < 400 THEN 1
        ELSE 0 
      END
    ) AS resp_score
  FROM cohort c
  LEFT JOIN (
    SELECT 
      stay_id,
      charttime,
      CASE 
        WHEN itemid IN (223835, 227287) THEN valuenum  -- FiO2
        ELSE NULL 
      END AS fio2,
      CASE 
        WHEN itemid IN (220224, 220739) THEN valuenum  -- PaO2
        ELSE NULL 
      END AS pao2,
      CASE 
        WHEN itemid IN (223848, 223849) THEN 1  -- Invasive vent
        WHEN itemid = 223850 THEN 0              -- Non-invasive
        ELSE NULL 
      END AS vent
    FROM `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE itemid IN (223835, 227287, 220224, 220739, 223848, 223849, 223850)
  ) ce
  ON c.stay_id = ce.stay_id
  AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id
),
sofa_coag AS (
  -- Coagulation: Platelets
  SELECT 
    c.stay_id,
    MIN(
      CASE
        WHEN platelet < 20 THEN 4
        WHEN platelet < 50 THEN 3
        WHEN platelet < 100 THEN 2
        WHEN platelet < 150 THEN 1
        ELSE 0
      END
    ) AS coag_score
  FROM cohort c
  LEFT JOIN (
    SELECT 
      stay_id,
      charttime,
      valuenum AS platelet
    FROM `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE itemid = 227457  -- Platelets
  ) ce
  ON c.stay_id = ce.stay_id
  AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id
),
sofa_liver AS (
  -- Liver: Bilirubin
  SELECT 
    c.stay_id,
    MIN(
      CASE
        WHEN bilirubin >= 12.0 THEN 4
        WHEN bilirubin >= 6.0 THEN 3
        WHEN bilirubin >= 2.0 THEN 2
        WHEN bilirubin >= 1.2 THEN 1
        ELSE 0
      END
    ) AS liver_score
  FROM cohort c
  LEFT JOIN (
    SELECT 
      stay_id,
      charttime,
      valuenum AS bilirubin
    FROM `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE itemid = 225690  -- Bilirubin
  ) ce
  ON c.stay_id = ce.stay_id
  AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id
),
sofa_cv AS (
  -- Cardiovascular: Vasopressors & MAP
  SELECT 
    c.stay_id,
    MIN(
      CASE
        WHEN vaso.norepinephrine > 0.1 OR vaso.epinephrine > 0.1 OR vaso.dopamine > 15 THEN 4
        WHEN vaso.norepinephrine > 0 OR vaso.epinephrine > 0 OR vaso.dopamine > 5 THEN 3
        WHEN vaso.dopamine > 0 OR vaso.dobutamine > 0 THEN 2
        WHEN map.map < 70 THEN 1
        ELSE 0
      END
    ) AS cv_score
  FROM cohort c
  LEFT JOIN (
    SELECT 
      ce.stay_id,
      AVG(valuenum) AS map
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN cohort co ON ce.stay_id = co.stay_id
    WHERE itemid = 220181
      AND ce.charttime BETWEEN co.intime AND DATETIME_ADD(co.intime, INTERVAL 48 HOUR)
    GROUP BY ce.stay_id, ce.charttime
  ) map
  ON c.stay_id = map.stay_id
  LEFT JOIN (
    SELECT 
      ie.stay_id,
      MAX(CASE WHEN itemid = 221906 THEN rate ELSE 0 END) AS norepinephrine,
      MAX(CASE WHEN itemid = 221289 THEN rate ELSE 0 END) AS epinephrine,
      MAX(CASE WHEN itemid = 221662 THEN rate ELSE 0 END) AS dopamine,
      MAX(CASE WHEN itemid = 221653 THEN rate ELSE 0 END) AS dobutamine
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
    INNER JOIN cohort co ON ie.stay_id = co.stay_id
    WHERE itemid IN (221906, 221289, 221662, 221653)
      AND starttime BETWEEN co.intime AND DATETIME_ADD(co.intime, INTERVAL 48 HOUR)
    GROUP BY ie.stay_id
  ) vaso
  ON c.stay_id = vaso.stay_id
  GROUP BY c.stay_id
),
sofa_cns AS (
  -- CNS: GCS
  SELECT 
    c.stay_id,
    MIN(
      CASE
        WHEN gcs < 6 THEN 4
        WHEN gcs < 9 THEN 3
        WHEN gcs < 12 THEN 2
        WHEN gcs < 14 THEN 1
        ELSE 0
      END
    ) AS cns_score
  FROM cohort c
  LEFT JOIN (
    SELECT 
      stay_id,
      charttime,
      MIN(valuenum) AS gcs  -- Worst GCS
    FROM `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE itemid = 226755  -- GCS
    GROUP BY stay_id, charttime
  ) ce
  ON c.stay_id = ce.stay_id
  AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id
),
sofa_renal AS (
  -- Renal: Creatinine & Urine Output
  SELECT 
    c.stay_id,
    MIN(
      CASE
        WHEN cr.creatinine >= 5.0 OR uo.urine_output < 200 THEN 4
        WHEN cr.creatinine >= 3.5 OR uo.urine_output < 500 THEN 3
        WHEN cr.creatinine >= 2.0 OR uo.urine_output < 700 THEN 2
        WHEN cr.creatinine >= 1.2 THEN 1
        ELSE 0
      END
    ) AS renal_score
  FROM cohort c
  LEFT JOIN (
    SELECT 
      stay_id,
      charttime,
      valuenum AS creatinine
    FROM `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE itemid = 220615  -- Creatinine
  ) cr
  ON c.stay_id = cr.stay_id
  AND cr.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  LEFT JOIN (
    SELECT 
      o.stay_id,
      SUM(CASE WHEN itemid = 227488 THEN value ELSE 0 END) AS urine_output
    FROM `physionet-data.mimiciv_3_1_icu.outputevents` o
    INNER JOIN cohort co ON o.stay_id = co.stay_id
    WHERE itemid = 227488
      AND charttime BETWEEN co.intime AND DATETIME_ADD(co.intime, INTERVAL 48 HOUR)
    GROUP BY o.stay_id
  ) uo
  ON c.stay_id = uo.stay_id
  GROUP BY c.stay_id
),
sofa_scores AS (
  -- Combine SOFA components
  SELECT 
    c.stay_id,
    COALESCE(r.resp_score, 0) 
    + COALESCE(co.coag_score, 0) 
    + COALESCE(l.liver_score, 0) 
    + COALESCE(cv.cv_score, 0) 
    + COALESCE(cn.cns_score, 0) 
    + COALESCE(re.renal_score, 0) AS sofa_score
  FROM cohort c
  LEFT JOIN sofa_resp r ON c.stay_id = r.stay_id
  LEFT JOIN sofa_coag co ON c.stay_id = co.stay_id
  LEFT JOIN sofa_liver l ON c.stay_id = l.stay_id
  LEFT JOIN sofa_cv cv ON c.stay_id = cv.stay_id
  LEFT JOIN sofa_cns cn ON c.stay_id = cn.stay_id
  LEFT JOIN sofa_renal re ON c.stay_id = re.stay_id
),
-- Lab Abnormalities (first 48 hours)
labs_septic AS (
  SELECT 
    c.stay_id,
    -- WBC
    MAX(CASE WHEN itemid = 51300 AND (valuenum < 4.5 OR valuenum > 11.0) THEN 1 ELSE 0 END) AS wbc_abnormal,
    -- Hemoglobin
    MAX(CASE WHEN itemid = 51222 AND valuenum < 12.0 THEN 1 ELSE 0 END) AS hgb_abnormal,
    -- Platelets
    MAX(CASE WHEN itemid = 51265 AND (valuenum < 150 OR valuenum > 400) THEN 1 ELSE 0 END) AS plt_abnormal,
    -- Sodium
    MAX(CASE WHEN itemid = 50983 AND (valuenum < 135 OR valuenum > 145) THEN 1 ELSE 0 END) AS na_abnormal,
    -- Potassium
    MAX(CASE WHEN itemid = 50971 AND (valuenum < 3.5 OR valuenum > 5.0) THEN 1 ELSE 0 END) AS k_abnormal,
    -- Creatinine
    MAX(CASE WHEN itemid = 50912 AND (valuenum < 0.5 OR valuenum > 1.2) THEN 1 ELSE 0 END) AS cr_abnormal,  -- Fixed range
    -- BUN
    MAX(CASE WHEN itemid = 51006 AND (valuenum < 7 OR valuenum > 20) THEN 1 ELSE 0 END) AS bun_abnormal
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id
    AND le.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  WHERE le.itemid IN (51300, 51222, 51265, 50983, 50971, 50912, 51006)  -- WBC, Hgb, Plt, Na, K, Cr, BUN
  GROUP BY c.stay_id
),
labs_general AS (
  SELECT 
    gc.stay_id,
    MAX(CASE WHEN itemid = 51300 AND (valuenum < 4.5 OR valuenum > 11.0) THEN 1 ELSE 0 END) AS wbc_abnormal,
    MAX(CASE WHEN itemid = 51222 AND valuenum < 12.0 THEN 1 ELSE 0 END) AS hgb_abnormal,
    MAX(CASE WHEN itemid = 51265 AND (valuenum < 150 OR valuenum > 400) THEN 1 ELSE 0 END) AS plt_abnormal,
    MAX(CASE WHEN itemid = 50983 AND (valuenum < 135 OR valuenum > 145) THEN 1 ELSE 0 END) AS na_abnormal,
    MAX(CASE WHEN itemid = 50971 AND (valuenum < 3.5 OR valuenum > 5.0) THEN 1 ELSE 0 END) AS k_abnormal,
    MAX(CASE WHEN itemid = 50912 AND (valuenum < 0.5 OR valuenum > 1.2) THEN 1 ELSE 0 END) AS cr_abnormal,
    MAX(CASE WHEN itemid = 51006 AND (valuenum < 7 OR valuenum > 20) THEN 1 ELSE 0 END) AS bun_abnormal
  FROM general_cohort gc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON gc.subject_id = le.subject_id
    AND le.charttime BETWEEN gc.intime AND DATETIME_ADD(gc.intime, INTERVAL 48 HOUR)
  WHERE le.itemid IN (51300, 51222, 51265, 50983, 50971, 50912, 51006)
  GROUP BY gc.stay_id
)
-- Final Output
SELECT 
  -- SOFA Score Distribution (Q1, Median, Q3, IQR)
  (SELECT PERCENTILE_CONT(sofa_score, 0.25) FROM sofa_scores) AS sofa_q1,
  (SELECT PERCENTILE_CONT(sofa_score, 0.5) FROM sofa_scores) AS sofa_median,
  (SELECT PERCENTILE_CONT(sofa_score, 0.75) FROM sofa_scores) AS sofa_q3,
  (SELECT PERCENTILE_CONT(sofa_score, 0.75) - PERCENTILE_CONT(sofa_score, 0.25) FROM sofa_scores) AS sofa_iqr,
  -- Lab Abnormalities (Septic Cohort)
  (SELECT AVG(wbc_abnormal) FROM labs_septic) AS septic_wbc_abnormal,
  (SELECT AVG(hgb_abnormal) FROM labs_septic) AS septic_hgb_abnormal,
  (SELECT AVG(plt_abnormal) FROM labs_septic) AS septic_plt_abnormal,
  (SELECT AVG(na_abnormal) FROM labs_septic) AS septic_na_abnormal,
  (SELECT AVG(k_abnormal) FROM labs_septic) AS septic_k_abnormal,
  (SELECT AVG(cr_abnormal) FROM labs_septic) AS septic_cr_abnormal,
  (SELECT AVG(bun_abnormal) FROM labs_septic) AS septic_bun_abnormal,
  -- Lab Abnormalities (General Cohort)
  (SELECT AVG(wbc_abnormal) FROM labs_general) AS general_wbc_abnormal,
  (SELECT AVG(hgb_abnormal) FROM labs_general) AS general_hgb_abnormal,
  (SELECT AVG(plt_abnormal) FROM labs_general) AS general_plt_abnormal,
  (SELECT AVG(na_abnormal) FROM labs_general) AS general_na_abnormal,
  (SELECT AVG(k_abnormal) FROM labs_general) AS general_k_abnormal,
  (SELECT AVG(cr_abnormal) FROM labs_general) AS general_cr_abnormal,
  (SELECT AVG(bun_abnormal) FROM labs_general) AS general_bun_abnormal,
  -- Cohort Outcomes
  (SELECT PERCENTILE_CONT(DATETIME_DIFF(dischtime, admittime, DAY), 0.25) FROM cohort) AS los_q1,
  (SELECT PERCENTILE_CONT(DATETIME_DIFF(dischtime, admittime, DAY), 0.5) FROM cohort) AS los_median,
  (SELECT PERCENTILE_CONT(DATETIME_DIFF(dischtime, admittime, DAY), 0.75) FROM cohort) AS los_q3,
  (SELECT AVG(hospital_expire_flag) FROM cohort) AS mortality_rate
FROM cohort
LIMIT 1;