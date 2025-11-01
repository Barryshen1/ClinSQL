WITH
-- 1. Get 60-70yo female patients
cohort_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 60 AND 70
),

-- 2. Get admissions with T2DM and HF
t2dm_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (
    -- ICD-10 E11.* or ICD-9 250.0x, 250.2x, 250.4x, 250.6x, 250.8x
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E11'))
    OR
    (icd_version = 9 AND (
      REGEXP_CONTAINS(icd_code, r'^250[.]0')
      OR REGEXP_CONTAINS(icd_code, r'^250[.]2')
      OR REGEXP_CONTAINS(icd_code, r'^250[.]4')
      OR REGEXP_CONTAINS(icd_code, r'^250[.]6')
      OR REGEXP_CONTAINS(icd_code, r'^250[.]8')
    ))
  )
),
hf_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50'))
    OR
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428'))
  )
),
cohort_admissions AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN cohort_patients p ON a.subject_id = p.subject_id
  INNER JOIN t2dm_hadm t ON a.hadm_id = t.hadm_id
  INNER JOIN hf_hadm h ON a.hadm_id = h.hadm_id
),

-- 3. Get ICU stays for cohort
cohort_icustays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN cohort_admissions ca ON i.subject_id = ca.subject_id AND i.hadm_id = ca.hadm_id
),

-- 4. Drug class definitions (for matching)
drug_class AS (
  SELECT 'antidiabetic' AS class, drug
  FROM UNNEST([
    'metformin', 'insulin', 'glipizide', 'glyburide', 'glimepiride', 'sitagliptin', 'linagliptin', 'empagliflozin', 'canagliflozin', 'dapagliflozin', 'liraglutide', 'exenatide', 'semaglutide'
  ]) AS drug
  UNION ALL
  SELECT 'beta_blocker', drug
  FROM UNNEST([
    'metoprolol', 'carvedilol', 'bisoprolol', 'atenolol', 'propranolol', 'labetalol'
  ]) AS drug
  UNION ALL
  SELECT 'ace_arb_arni', drug
  FROM UNNEST([
    'lisinopril', 'enalapril', 'ramipril', 'captopril', 'benazepril', 'losartan', 'valsartan', 'candesartan', 'irbesartan', 'olmesartan', 'sacubitril/valsartan'
  ]) AS drug
  UNION ALL
  SELECT 'loop_diuretic', drug
  FROM UNNEST([
    'furosemide', 'bumetanide', 'torsemide'
  ]) AS drug
),

-- 5. Medication initiations (prescriptions)
med_initiations_presc AS (
  SELECT
    s.stay_id,
    s.intime,
    s.outtime,
    dc.class,
    MIN(p.starttime) AS first_starttime
  FROM cohort_icustays s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON s.subject_id = p.subject_id AND s.hadm_id = p.hadm_id
  INNER JOIN drug_class dc
    ON LOWER(p.drug) LIKE CONCAT('%', LOWER(dc.drug), '%')
  WHERE p.starttime >= s.intime
    AND p.starttime < s.outtime
  GROUP BY s.stay_id, s.intime, s.outtime, dc.class
),

-- 6. Medication initiations (administration)
med_initiations_emar AS (
  SELECT
    s.stay_id,
    s.intime,
    s.outtime,
    dc.class,
    MIN(e.charttime) AS first_charttime
  FROM cohort_icustays s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON s.subject_id = e.subject_id AND s.hadm_id = e.hadm_id
  INNER JOIN drug_class dc
    ON LOWER(e.medication) LIKE CONCAT('%', LOWER(dc.drug), '%')
  WHERE e.charttime >= s.intime
    AND e.charttime < s.outtime
  GROUP BY s.stay_id, s.intime, s.outtime, dc.class
),

-- 7. Combine initiations (take earliest from either source)
med_initiations AS (
  SELECT
    stay_id,
    intime,
    outtime,
    class,
    MIN(first_time) AS first_time
  FROM (
    SELECT stay_id, intime, outtime, class, first_starttime AS first_time
    FROM med_initiations_presc
    UNION ALL
    SELECT stay_id, intime, outtime, class, first_charttime AS first_time
    FROM med_initiations_emar
  )
  GROUP BY stay_id, intime, outtime, class
),

-- 8. For each stay/class, flag initiation in first 48h and/or final 24h
med_initiation_flags AS (
  SELECT
    stay_id,
    class,
    CASE WHEN first_time >= intime AND first_time < DATETIME_ADD(intime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END AS in_first_48h,
    CASE WHEN first_time >= DATETIME_SUB(outtime, INTERVAL 24 HOUR) AND first_time < outtime THEN 1 ELSE 0 END AS in_final_24h
  FROM med_initiations
),

-- 9. For denominator: total eligible ICU stays per class
eligible_stays AS (
  SELECT stay_id, class
  FROM cohort_icustays
  CROSS JOIN (SELECT DISTINCT class FROM drug_class)
),

-- 10. Aggregate results
agg AS (
  SELECT
    e.class,
    COUNT(e.stay_id) AS n_stays,
    SUM(COALESCE(m.in_first_48h, 0)) AS n_first_48h,
    SUM(COALESCE(m.in_final_24h, 0)) AS n_final_24h
  FROM eligible_stays e
  LEFT JOIN med_initiation_flags m
    ON e.stay_id = m.stay_id AND e.class = m.class
  GROUP BY e.class
)

SELECT
  class,
  n_stays,
  ROUND(100.0 * n_first_48h / n_stays, 1) AS pct_first_48h,
  ROUND(100.0 * n_final_24h / n_stays, 1) AS pct_final_24h,
  ROUND(100.0 * (n_first_48h - n_final_24h) / n_stays, 1) AS abs_diff_pp
FROM agg
ORDER BY class;