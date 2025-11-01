with a diagnosis of
-- heart failure and an ICU stay.
-- It then calculates key metrics for this cohort: median OASIS risk score, 30-day mortality,
-- major complication rate, and average length of stay for survivors.
-- Finally, it contextualizes the cohort's risk by providing its percentile rank against all
-- female ICU patients in the same age group.

WITH
  -- Step 1: Define the base demographic cohort: females aged 43-53 at admission
  demographics AS (
    SELECT
      p.subject_id,
      p.gender,
      p.dod,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.admission_type,
      a.hospital_expire_flag,
      (
        EXTRACT(
          YEAR
          FROM a.admittime
        ) - p.anchor_year
      ) + p.anchor_age AS age_at_admission
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'F'
      AND (
        (
          EXTRACT(
            YEAR
            FROM a.admittime
          ) - p.anchor_year
        ) + p.anchor_age
      ) BETWEEN 43 AND 53
  ),
  -- Step 2: Identify the first ICU stay for each hospital admission in the base cohort
  first_icu_stays AS (
    SELECT
      d.hadm_id,
      d.admittime,
      d.dischtime,
      d.dod,
      d.hospital_expire_flag,
      i.stay_id,
      i.intime,
      i.outtime,
      d.age_at_admission,
      d.admission_type,
      DATETIME_DIFF(i.intime, d.admittime, HOUR) AS pre_icu_los_hours,
      -- Rank ICU stays to select only the first one per admission
      ROW_NUMBER() OVER (
        PARTITION BY
          i.hadm_id
        ORDER BY
          i.intime
      ) AS rn
    FROM
      demographics AS d
      JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i ON d.hadm_id = i.hadm_id
  ),
  -- Step 3: Define the target cohort (Heart Failure) and reference cohort (all others)
  cohorts AS (
    SELECT
      f.hadm_id,
      f.stay_id,
      f.intime,
      f.outtime,
      f.admittime,
      f.dischtime,
      f.dod,
      f.hospital_expire_flag,
      f.age_at_admission,
      f.admission_type,
      f.pre_icu_los_hours,
      -- Flag for Heart Failure diagnosis
      MAX(
        CASE
          WHEN diag.icd_code LIKE '428%'
          OR diag.icd_code LIKE 'I50%' THEN 1
          ELSE 0
        END
      ) AS is_hf_cohort
    FROM
      first_icu_stays AS f
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag ON f.hadm_id = diag.hadm_id
    WHERE
      f.rn = 1 -- Only the first ICU stay
    GROUP BY
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      11
  ),
  -- Step 4: Extract variables for OASIS score calculation from the first 24h of the ICU stay
  t_gcs AS (
    SELECT
      c.stay_id,
      MIN(ce.valuenum) AS mingcs
    FROM
      cohorts AS c
      JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce ON c.stay_id = ce.stay_id
    WHERE
      ce.itemid = 226758 -- GCS Total
      AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    GROUP BY
      c.stay_id
  ),
  t_hr AS (
    SELECT
      c.stay_id,
      MAX(ce.valuenum) AS maxhr
    FROM
      cohorts AS c
      JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce ON c.stay_id = ce.stay_id
    WHERE
      ce.itemid = 220045 -- Heart Rate
      AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    GROUP BY
      c.stay_id
  ),
  t_mbp AS (
    SELECT
      c.stay_id,
      MIN(ce.valuenum) AS minmbp
    FROM
      cohorts AS c
      JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce ON c.stay_id = ce.stay_id
    WHERE
      ce.itemid IN (220181, 220052) -- NBP Mean, Arterial BP Mean
      AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    GROUP BY
      c.stay_id
  ),
  t_resp AS (
    SELECT
      c.stay_id,
      MAX(ce.valuenum) AS maxresp
    FROM
      cohorts AS c
      JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce ON c.stay_id = ce.stay_id
    WHERE
      ce.itemid = 220210 -- Respiratory Rate
      AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    GROUP BY
      c.stay_id
  ),
  t_temp_max AS (
    SELECT
      c.stay_id,
      MAX(ce.valuenum) AS maxtemp
    FROM
      cohorts AS c
      JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce ON c.stay_id = ce.stay_id
    WHERE
      ce.itemid IN (223762, 223761) -- Temp C, Temp F (converted in some systems)
      AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    GROUP BY
      c.stay_id
  ),
  t_temp_min AS (
    SELECT
      c.stay_id,
      MIN(ce.valuenum) AS mintemp
    FROM
      cohorts AS c
      JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce ON c.stay_id = ce.stay_id
    WHERE
      ce.itemid IN (223762, 223761) -- Temp C, Temp F
      AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    GROUP BY
      c.stay_id
  ),
  t_urine AS (
    SELECT
      c.stay_id,
      SUM(oe.value) AS urineoutput
    FROM
      cohorts AS c
      JOIN `physionet-data.mimiciv_3_1_icu.outputevents` AS oe ON c.stay_id = oe.stay_id
    WHERE
      oe.itemid IN (
        226559, -- Foley
        226561, -- Condom Cath
        227489, -- Urine Guard
        226563, -- Toileting
        226564, -- Urinal
        226567 -- Straight Cath
      )
      AND oe.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    GROUP BY
      c.stay_id
  ),
  t_vent AS (
    SELECT
      c.stay_id,
      MAX(
        CASE
          WHEN pe.itemid IS NOT NULL THEN 1
          ELSE 0
        END
      ) AS mechvent
    FROM
      cohorts AS c
      LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe ON c.stay_id = pe.stay_id
      AND pe.itemid IN (
        225792 -- Invasive Ventilation
        -- Corrected: Removed itemid 224685 as it's from chartevents, not procedureevents
      )
      AND pe.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    GROUP BY
      c.stay_id
  ),
  -- Step 5: Calculate OASIS score for each patient in the reference cohort
  oasis_scores AS (
    SELECT
      c.hadm_id,
      c.is_hf_cohort,
      c.admittime,
      c.dischtime,
      c.dod,
      c.hospital_expire_flag,
      (
        CASE
          WHEN c.age_at_admission > 88 THEN 10
          WHEN c.age_at_admission BETWEEN 77 AND 88 THEN 9
          WHEN c.age_at_admission BETWEEN 64 AND 76 THEN 9
          WHEN c.age_at_admission BETWEEN 54 AND 63 THEN 5
          WHEN c.age_at_admission BETWEEN 24 AND 53 THEN 2
          ELSE 0
        END
      ) + (
        CASE
          WHEN c.pre_icu_los_hours > 310 THEN 5
          WHEN c.pre_icu_los_hours > 4.9 THEN 3
          ELSE 0
        END
      ) + (
        CASE
          WHEN gcs.mingcs < 8 THEN 10
          WHEN gcs.mingcs <= 13 THEN 4
          ELSE 0
        END
      ) + (
        CASE
          WHEN hr.maxhr > 128 THEN 6
          WHEN hr.maxhr > 109 THEN 3
          ELSE 0
        END
      ) + (
        CASE
          WHEN mbp.minmbp < 32.6 THEN 4
          WHEN mbp.minmbp < 52.3 THEN 2
          ELSE 0
        END
      ) + (
        CASE
          WHEN resp.maxresp > 48 THEN 9
          WHEN resp.maxresp > 33 THEN 6
          WHEN resp.maxresp > 22 THEN 1
          ELSE 0
        END
      ) + (
        GREATEST(
          CASE
            WHEN temp_max.maxtemp > 39.5 THEN 6
            ELSE 0
          END,
          CASE
            WHEN temp_min.mintemp < 35.4 THEN 2
            ELSE 0
          END
        )
      ) + (
        CASE
          WHEN u.urineoutput < 141 THEN 10
          WHEN u.urineoutput < 383 THEN 8
          WHEN u.urineoutput < 671 THEN 5
          ELSE 0
        END
      ) + (
        CASE
          WHEN v.mechvent = 1 THEN 9
          ELSE 0
        END
      ) + (
        CASE
          WHEN c.admission_type != 'ELECTIVE' THEN 6
          ELSE 0
        END
      ) AS oasis_score
    FROM
      cohorts AS c
      LEFT JOIN t_gcs AS gcs ON c.stay_id = gcs.stay_id
      LEFT JOIN t_hr AS hr ON c.stay_id = hr.stay_id
      LEFT JOIN t_mbp AS mbp ON c.stay_id = mbp.stay_id
      LEFT JOIN t_resp AS resp ON c.stay_id = resp.stay_id
      LEFT JOIN t_temp_max AS temp_max ON c.stay_id = temp_max.stay_id
      LEFT JOIN t_temp_min AS temp_min ON c.stay_id = temp_min.stay_id
      LEFT JOIN t_urine AS u ON c.stay_id = u.stay_id
      LEFT JOIN t_vent AS v ON c.stay_id = v.stay_id
  ),
  -- Step 6: Identify major complications for all admissions in the base cohort
  complications AS (
    SELECT
      hadm_id,
      MAX(
        CASE
          -- Look for specific ICD codes with seq_num > 1 (not primary diagnosis)
          WHEN icd_code LIKE '584%'
          OR icd_code LIKE 'N17%' -- AKI
          OR icd_code IN ('99591', '99592', '78552')
          OR icd_code LIKE 'A41%'
          OR icd_code LIKE 'R65.2%' -- Sepsis
          OR icd_code LIKE '410%'
          OR icd_code LIKE 'I21%'
          OR icd_code LIKE 'I22%' -- MI
          OR icd_code IN ('433', '434', '436')
          OR icd_code LIKE 'I60%'
          OR icd_code LIKE 'I61%'
          OR icd_code LIKE 'I62%'
          OR icd_code LIKE 'I63%'
          OR icd_code LIKE 'I64%' THEN 1 -- Stroke
          ELSE 0
        END
      ) AS has_major_complication
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      seq_num > 1
    GROUP BY
      hadm_id
  ),
  -- Step 7: Combine all data for final analysis
  final_data AS (
    SELECT
      o.hadm_id,
      o.is_hf_cohort,
      o.oasis_score,
      DATETIME_DIFF(o.dischtime, o.admittime, HOUR) / 24.0 AS hospital_los,
      o.hospital_expire_flag,
      CASE
        WHEN o.dod IS NOT NULL
        AND DATE_DIFF(DATE(o.dod), DATE(o.admittime), DAY) <= 30 THEN 1
        ELSE 0
      END AS thirty_day_mortality,
      COALESCE(c.has_major_complication, 0) AS has_major_complication
    FROM
      oasis_scores AS o
      LEFT JOIN complications AS c ON o.hadm_id = c.hadm_id
  ),
  -- Step 8: Calculate metrics for the target cohort
  target_cohort_metrics AS (
    SELECT
      APPROX_QUANTILES(oasis_score, 100) AS oasis_quantiles,
      AVG(thirty_day_mortality) * 100 AS thirty_day_mortality_rate,
      AVG(has_major_complication) * 100 AS major_complication_rate,
      AVG(
        CASE
          WHEN hospital_expire_flag = 0 THEN hospital_los
          ELSE NULL
        END
      ) AS avg_los_survivors
    FROM
      final_data
    WHERE
      is_hf_cohort = 1
  ) -- Final Step: Present the results and calculate the risk percentile
SELECT
  -- Cohort-specific metrics
  oasis_quantiles [
    OFFSET
      (50)
  ] AS median_risk_score,
  (
    oasis_quantiles [
      OFFSET
        (75)
    ] - oasis_quantiles [
      OFFSET
        (25)
    ]
  ) AS iqr_risk_score,
  thirty_day_mortality_rate,
  major_complication_rate,
  avg_los_survivors,
  -- Risk percentile calculation
  (
    SELECT
      (
        COUNTIF(
          oasis_score < (
            SELECT
              oasis_quantiles [
            OFFSET
              (50)
          ]
            FROM
              target_cohort_metrics
          )
        ) * 100.0
      ) / COUNT(oasis_score)
    FROM
      final_data
    WHERE
      oasis_score IS NOT NULL
  ) AS risk_percentile_vs_all_females_43_53_icu
FROM
  target_cohort_metrics;