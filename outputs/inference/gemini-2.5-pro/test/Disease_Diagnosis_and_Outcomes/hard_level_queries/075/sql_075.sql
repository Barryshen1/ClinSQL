WITH
  -- 1. Define the base cohort of female patients aged 44-54 at admission
  base_admissions AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      p.dod,
      a.hospital_expire_flag,
      (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'F'
  ),
  cohort_admissions AS (
    SELECT
      *
    FROM
      base_admissions
    WHERE
      age_at_admission BETWEEN 44 AND 54
  ),
  -- 2. Identify admissions with an Intracranial Hemorrhage (ICH) diagnosis
  ich_admissions AS (
    SELECT DISTINCT
      hadm_id,
      1 AS is_ich
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('430', '431', '432'))
      OR (
        icd_version = 10
        AND (
          STARTS_WITH(icd_code, 'I60')
          OR STARTS_WITH(icd_code, 'I61')
          OR STARTS_WITH(icd_code, 'I62')
        )
      )
  ),
  -- 3. Combine base cohort with ICH flag
  cohort AS (
    SELECT
      ca.*,
      COALESCE(ia.is_ich, 0) AS is_ich_cohort
    FROM
      cohort_admissions AS ca
    LEFT JOIN
      ich_admissions AS ia
      ON ca.hadm_id = ia.hadm_id
  ),
  -- 4. Calculate First-Day SOFA score for each ICU stay
  -- The following CTEs are un-nested from the original `sofa` CTE to fix the syntax error.
  pao2fio2_data AS (
    SELECT
      ie.stay_id,
      CASE
        WHEN ce.itemid = 223835
        THEN
          CASE
            WHEN ce.valuenum > 0 AND ce.valuenum <= 1 THEN ce.valuenum * 100
            WHEN ce.valuenum > 1 AND ce.valuenum <= 100 THEN ce.valuenum
            ELSE NULL
          END
        ELSE NULL
      END AS fio2,
      CASE WHEN le.itemid = 50821 THEN le.valuenum ELSE NULL END AS pao2
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS ie
    INNER JOIN `cohort`
      ON ie.hadm_id = cohort.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON ie.stay_id = ce.stay_id AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON ie.subject_id = le.subject_id AND le.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
    WHERE
      (ce.itemid = 223835 OR le.itemid = 50821)
  ),
  vaso_data AS (
    SELECT
      icu.stay_id,
      MAX(CASE WHEN mv.itemid = 221906 THEN mv.rate END) AS rate_norepinephrine,
      MAX(CASE WHEN mv.itemid = 221289 THEN mv.rate END) AS rate_epinephrine,
      MAX(CASE WHEN mv.itemid = 221662 THEN mv.rate END) AS rate_dopamine,
      MAX(CASE WHEN mv.itemid = 221653 THEN mv.rate END) AS rate_dobutamine
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `cohort`
      ON icu.hadm_id = cohort.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` AS mv
      ON icu.stay_id = mv.stay_id
    WHERE
      mv.starttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL '1' DAY)
      AND mv.itemid IN (221906, 221289, 221662, 221653)
      AND mv.statusdescription != 'Rewritten' -- Exclude invalid entries
      AND mv.rate > 0
    GROUP BY
      icu.stay_id
  ),
  sofa_components AS (
    SELECT
      ie.stay_id,
      MIN(p.pao2 / p.fio2) AS pao2fio2_min,
      -- REFINED: Use more common MIMIC-IV GCS itemids
      MIN(ce_gcs.valuenum) AS gcs_min,
      MIN(ce_map.valuenum) AS map_min,
      MAX(le_bili.valuenum) AS bilirubin_max,
      MIN(le_plat.valuenum) AS platelet_min,
      MAX(le_creat.valuenum) AS creatinine_max,
      SUM(oe.value) AS urine_output
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS ie
    INNER JOIN `cohort`
      ON ie.hadm_id = cohort.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce_gcs
      ON ie.stay_id = ce_gcs.stay_id AND ce_gcs.itemid IN (198, 220739) AND ce_gcs.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce_map
      ON ie.stay_id = ce_map.stay_id AND ce_map.itemid = 220052 AND ce_map.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le_bili
      ON ie.subject_id = le_bili.subject_id AND le_bili.itemid = 50885 AND le_bili.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le_plat
      ON ie.subject_id = le_plat.subject_id AND le_plat.itemid = 51265 AND le_plat.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le_creat
      ON ie.subject_id = le_creat.subject_id AND le_creat.itemid = 50912 AND le_creat.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.outputevents` AS oe
      ON ie.stay_id = oe.stay_id AND oe.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
    LEFT JOIN pao2fio2_data AS p
      ON ie.stay_id = p.stay_id
    GROUP BY
      ie.stay_id
  ),
  sofa_scores AS (
    SELECT
      ie.hadm_id,
      (
        -- Respiration
        CASE WHEN s.pao2fio2_min < 100 THEN 4 WHEN s.pao2fio2_min < 200 THEN 3 WHEN s.pao2fio2_min < 300 THEN 2 WHEN s.pao2fio2_min < 400 THEN 1 ELSE 0 END
        -- Coagulation
        + CASE WHEN s.platelet_min < 20 THEN 4 WHEN s.platelet_min < 50 THEN 3 WHEN s.platelet_min < 100 THEN 2 WHEN s.platelet_min < 150 THEN 1 ELSE 0 END
        -- Liver
        + CASE WHEN s.bilirubin_max >= 12.0 THEN 4 WHEN s.bilirubin_max >= 6.0 THEN 3 WHEN s.bilirubin_max >= 2.0 THEN 2 WHEN s.bilirubin_max >= 1.2 THEN 1 ELSE 0 END
        -- Cardiovascular
        + CASE
          WHEN COALESCE(v.rate_dopamine, 0) > 15 OR COALESCE(v.rate_epinephrine, 0) > 0.1 OR COALESCE(v.rate_norepinephrine, 0) > 0.1 THEN 4
          WHEN COALESCE(v.rate_dopamine, 0) > 5 OR (COALESCE(v.rate_epinephrine, 0) > 0 AND COALESCE(v.rate_epinephrine, 0) <= 0.1) OR (COALESCE(v.rate_norepinephrine, 0) > 0 AND COALESCE(v.rate_norepinephrine, 0) <= 0.1) THEN 3
          WHEN COALESCE(v.rate_dopamine, 0) > 0 OR COALESCE(v.rate_dobutamine, 0) > 0 THEN 2
          WHEN s.map_min < 70 THEN 1
          ELSE 0
        END
        -- CNS
        + CASE WHEN s.gcs_min < 6 THEN 4 WHEN s.gcs_min < 10 THEN 3 WHEN s.gcs_min < 13 THEN 2 WHEN s.gcs_min < 15 THEN 1 ELSE 0 END
        -- Renal
        + GREATEST(
          CASE WHEN s.creatinine_max >= 5.0 THEN 4 WHEN s.creatinine_max >= 3.5 THEN 3 WHEN s.creatinine_max >= 2.0 THEN 2 WHEN s.creatinine_max >= 1.2 THEN 1 ELSE 0 END,
          CASE WHEN s.urine_output < 200 THEN 4 WHEN s.urine_output < 500 THEN 3 ELSE 0 END
        )
      ) AS sofa_score
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS ie
    INNER JOIN `cohort`
      ON ie.hadm_id = cohort.hadm_id
    LEFT JOIN sofa_components AS s
      ON ie.stay_id = s.stay_id
    LEFT JOIN vaso_data AS v
      ON ie.stay_id = v.stay_id
  ),
  hadm_sofa AS (
    SELECT
      hadm_id,
      MAX(sofa_score) AS max_sofa_score
    FROM
      sofa_scores
    GROUP BY
      hadm_id
  ),
  -- 5. Identify major complications (Sepsis, AKI, ARDS)
  complications AS (
    SELECT DISTINCT
      hadm_id,
      1 AS has_complication
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      (icd_version = 9 AND (STARTS_WITH(icd_code, '9959') OR icd_code = '78552' OR STARTS_WITH(icd_code, '584') OR icd_code IN ('51882', '5185')))
      OR (icd_version = 10 AND (STARTS_WITH(icd_code, 'A40') OR STARTS_WITH(icd_code, 'A41') OR STARTS_WITH(icd_code, 'R652') OR STARTS_WITH(icd_code, 'N17') OR icd_code = 'J80'))
  ),
  -- 6. Consolidate all data per admission
  final_data AS (
    SELECT
      c.hadm_id,
      c.is_ich_cohort,
      hs.max_sofa_score,
      DATE_DIFF(c.dischtime, c.admittime, DAY) AS hospital_los,
      c.hospital_expire_flag,
      (CASE WHEN c.dod IS NOT NULL AND DATE_DIFF(c.dod, c.admittime, DAY) <= 90 THEN 1 ELSE 0 END) AS is_90_day_mortality,
      COALESCE(comp.has_complication, 0) AS has_complication
    FROM
      cohort AS c
    LEFT JOIN
      hadm_sofa AS hs
      ON c.hadm_id = hs.hadm_id
    LEFT JOIN
      complications AS comp
      ON c.hadm_id = comp.hadm_id
  ),
  -- 7. Calculate median SOFA for the ICH cohort to use for percentile ranking
  ich_median_sofa AS (
    SELECT
      APPROX_QUANTILES(max_sofa_score, 2)[OFFSET(1)] AS median_sofa
    FROM
      final_data
    WHERE
      is_ich_cohort = 1 AND max_sofa_score IS NOT NULL
  ),
  -- 8. Calculate percentile of the ICH median SOFA within the General (non-ICH) cohort
  sofa_percentile AS (
    SELECT
      SAFE_DIVIDE(
        (SELECT COUNT(*) FROM final_data WHERE is_ich_cohort = 0 AND max_sofa_score IS NOT NULL AND max_sofa_score <= ims.median_sofa),
        (SELECT COUNT(*) FROM final_data WHERE is_ich_cohort = 0 AND max_sofa_score IS NOT NULL)
      ) * 100 AS matched_risk_percentile
    FROM
      ich_median_sofa AS ims
  )
-- 9. Final aggregation and presentation
SELECT
  CASE
    WHEN fd.is_ich_cohort = 1 THEN 'Female, 44-54, with Intracranial Hemorrhage'
    ELSE 'Female, 44-54, All Inpatients (excl. ICH)'
  END AS cohort,
  -- Median (IQR) Risk Score
  CONCAT(
    CAST(APPROX_QUANTILES(max_sofa_score, 100 IGNORE NULLS)[OFFSET(50)] AS STRING),
    ' (',
    CAST(APPROX_QUANTILES(max_sofa_score, 100 IGNORE NULLS)[OFFSET(25)] AS STRING),
    ' - ',
    CAST(APPROX_QUANTILES(max_sofa_score, 100 IGNORE NULLS)[OFFSET(75)] AS STRING),
    ')'
  ) AS median_iqr_sofa_score,
  -- 90-Day Mortality Rate
  AVG(is_90_day_mortality) * 100 AS mortality_rate_90_day_percent,
  -- Major Complication Rate
  AVG(has_complication) * 100 AS major_complication_rate_percent,
  -- Median Survivor LOS
  APPROX_QUANTILES(IF(hospital_expire_flag = 0, hospital_los, NULL), 100 IGNORE NULLS)[OFFSET(50)] AS median_survivor_los_days,
  -- Matched Risk Percentile (repeated on both rows for context)
  sp.matched_risk_percentile
FROM
  final_data AS fd
CROSS JOIN
  sofa_percentile AS sp
-- We analyze the ICH cohort vs the non-ICH cohort for a cleaner comparison
GROUP BY
  cohort,
  sp.matched_risk_percentile,
  fd.is_ich_cohort
ORDER BY
  fd.is_ich_cohort DESC;