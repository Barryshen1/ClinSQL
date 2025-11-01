WITH
  -- Step 1: Define the base cohorts of male patients aged 59-69, and flag DKA admissions.
  cohort_definition AS (
    SELECT
      pat.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      pat.dod,
      MAX(
        CASE
          WHEN dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 5) IN ('250.10', '250.11', '250.12', '250.13')
            THEN 1
          WHEN dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 4) IN ('E10.10', 'E11.10', 'E13.10') -- with and without coma
            THEN 1
          ELSE 0
        END
      ) AS is_dka_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON pat.subject_id = adm.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    WHERE
      pat.gender = 'M'
      -- Correctly calculate age at admission instead of using anchor_age as a proxy
      AND (DATETIME_DIFF(adm.admittime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR) + pat.anchor_age) BETWEEN 59 AND 69
    GROUP BY
      pat.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      pat.dod
  ),
  -- Step 2: Flag admissions with AKI or ARDS diagnoses.
  comorbidities AS (
    SELECT
      dx.hadm_id,
      MAX(
        CASE
          WHEN dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) = '584'
            THEN 1
          WHEN dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) = 'N17'
            THEN 1
          ELSE 0
        END
      ) AS has_aki,
      MAX(
        CASE
          WHEN dx.icd_version = 9 AND dx.icd_code = '518.82'
            THEN 1
          WHEN dx.icd_version = 10 AND dx.icd_code = 'J80'
            THEN 1
          ELSE 0
        END
      ) AS has_ards
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx -- FIX: Added alias 'dx' here
    GROUP BY
      dx.hadm_id
  ),
  -- Step 3: Calculate SOFA score for the first 24 hours of the first ICU stay.
  icu_base AS (
    SELECT
      co.hadm_id,
      icu.intime,
      DATETIME_ADD(icu.intime, INTERVAL 24 HOUR) AS endtime
    FROM cohort_definition AS co
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      ON co.hadm_id = icu.hadm_id
    QUALIFY
      ROW_NUMBER() OVER (PARTITION BY co.hadm_id ORDER BY icu.intime) = 1
  ),
  sofa_components AS (
    SELECT
      ib.hadm_id,
      -- Respiration: PaO2/FiO2 ratio. Corrected to robustly calculate the ratio.
      (
        (SELECT MIN(le.valuenum) FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le WHERE le.hadm_id = ib.hadm_id AND le.itemid = 50821 AND le.charttime BETWEEN ib.intime AND ib.endtime)
         /
        (SELECT MAX(CASE WHEN ce.valuenum > 1 THEN ce.valuenum / 100 ELSE ce.valuenum END) FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce WHERE ce.hadm_id = ib.hadm_id AND ce.itemid = 223835 AND ce.valuenum > 0 AND ce.charttime BETWEEN ib.intime AND ib.endtime)
      ) AS pao2_fio2_ratio,
      -- Coagulation: Platelets
      (SELECT MIN(le.valuenum) FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le WHERE le.hadm_id = ib.hadm_id AND le.itemid = 51265 AND le.charttime BETWEEN ib.intime AND ib.endtime) AS min_platelet,
      -- Liver: Bilirubin
      (SELECT MAX(le.valuenum) FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le WHERE le.hadm_id = ib.hadm_id AND le.itemid = 50885 AND le.charttime BETWEEN ib.intime AND ib.endtime) AS max_bilirubin,
      -- Cardiovascular: MAP and Vasopressors
      (SELECT MIN(ce.valuenum) FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce WHERE ce.hadm_id = ib.hadm_id AND ce.itemid IN (220052, 220181, 225312) AND ce.charttime BETWEEN ib.intime AND ib.endtime) AS min_map,
      (SELECT MAX(CASE WHEN ie.itemid IN (221906, 221289, 221662, 221653) THEN 1 ELSE 0 END) FROM `physionet-data.mimiciv_3_1_icu.inputevents` AS ie WHERE ie.hadm_id = ib.hadm_id AND ie.starttime BETWEEN ib.intime AND ib.endtime) AS vaso_flag,
      -- CNS: GCS
      (SELECT MIN(ce.valuenum) FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce WHERE ce.hadm_id = ib.hadm_id AND ce.itemid = 220739 AND ce.charttime BETWEEN ib.intime AND ib.endtime) AS min_gcs,
      -- Renal: Creatinine
      (SELECT MAX(le.valuenum) FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le WHERE le.hadm_id = ib.hadm_id AND le.itemid = 50912 AND le.charttime BETWEEN ib.intime AND ib.endtime) AS max_creatinine
    FROM icu_base AS ib
  ),
  sofa_scores AS (
    SELECT
      hadm_id,
      CASE WHEN pao2_fio2_ratio < 100 THEN 4 WHEN pao2_fio2_ratio < 200 THEN 3 WHEN pao2_fio2_ratio < 300 THEN 2 WHEN pao2_fio2_ratio < 400 THEN 1 ELSE 0 END AS respiration_score,
      CASE WHEN min_platelet < 20 THEN 4 WHEN min_platelet < 50 THEN 3 WHEN min_platelet < 100 THEN 2 WHEN min_platelet < 150 THEN 1 ELSE 0 END AS coagulation_score,
      CASE WHEN max_bilirubin >= 12.0 THEN 4 WHEN max_bilirubin >= 6.0 THEN 3 WHEN max_bilirubin >= 2.0 THEN 2 WHEN max_bilirubin >= 1.2 THEN 1 ELSE 0 END AS liver_score,
      CASE WHEN vaso_flag = 1 THEN 2 WHEN min_map < 70 THEN 1 ELSE 0 END AS cardiovascular_score, -- Simplified: any vaso gets 2 points
      CASE WHEN min_gcs <= 6 THEN 4 WHEN min_gcs <= 9 THEN 3 WHEN min_gcs <= 12 THEN 2 WHEN min_gcs <= 14 THEN 1 ELSE 0 END AS cns_score,
      CASE WHEN max_creatinine >= 5.0 THEN 4 WHEN max_creatinine >= 3.5 THEN 3 WHEN max_creatinine >= 2.0 THEN 2 WHEN max_creatinine >= 1.2 THEN 1 ELSE 0 END AS renal_score
    FROM sofa_components
  ),
  sofa_total AS (
    SELECT
      hadm_id,
      (respiration_score + coagulation_score + liver_score + cardiovascular_score + cns_score + renal_score) AS risk_score
    FROM sofa_scores
  ),
  -- Step 4: Combine all data for final analysis.
  final_data AS (
    SELECT
      co.hadm_id,
      co.is_dka_admission,
      (co.dod IS NOT NULL AND DATETIME_DIFF(co.dod, co.admittime, DAY) BETWEEN 0 AND 30) AS is_mort_30,
      DATETIME_DIFF(co.dischtime, co.admittime, DAY) AS los_hosp,
      cm.has_aki,
      cm.has_ards,
      sofa.risk_score
    FROM cohort_definition AS co
    LEFT JOIN comorbidities AS cm
      ON co.hadm_id = cm.hadm_id
    LEFT JOIN sofa_total AS sofa
      ON co.hadm_id = sofa.hadm_id
  ),
  -- Step 5: Aggregate statistics for each cohort.
  group_stats AS (
    SELECT
      CASE WHEN is_dka_admission = 1 THEN 'DKA (59-69, M)' ELSE 'General (59-69, M)' END AS cohort,
      AVG(risk_score) AS mean_risk_score,
      AVG(IF(is_mort_30, 1.0, 0.0)) AS mortality_30_day_rate,
      AVG(IF(has_aki = 1, 1.0, 0.0)) AS aki_rate,
      AVG(IF(has_ards = 1, 1.0, 0.0)) AS ards_rate,
      AVG(IF(NOT is_mort_30, los_hosp, NULL)) AS survivor_los_days
    FROM final_data
    GROUP BY
      cohort
  ),
  -- Step 6: Calculate the percentile of the DKA group's mean risk score in the general population.
  percentile_calc AS (
    SELECT
      (
        SELECT
          -- Count how many in the general pop have a score lower than the DKA group's average score
          COUNTIF(fd.risk_score < (SELECT gs.mean_risk_score FROM group_stats AS gs WHERE gs.cohort LIKE 'DKA%')) * 100.0
          / -- Divide by the total number of general pop patients with a score
          COUNT(fd.risk_score)
        FROM final_data AS fd
        WHERE
          fd.is_dka_admission = 0 AND fd.risk_score IS NOT NULL
      ) AS dka_risk_percentile_in_gen_pop
  )
-- Final Select: Combine aggregated stats with the calculated percentile.
SELECT
  gs.cohort,
  ROUND(gs.mean_risk_score, 2) AS mean_calculated_risk_score,
  ROUND(gs.mortality_30_day_rate * 100, 2) AS thirty_day_mortality_rate_pct,
  ROUND(gs.aki_rate * 100, 2) AS aki_rate_pct,
  ROUND(gs.ards_rate * 100, 2) AS ards_rate_pct,
  ROUND(gs.survivor_los_days, 2) AS mean_survivor_los_days,
  -- Display the percentile only for the DKA cohort row
  CASE
    WHEN gs.cohort LIKE 'DKA%'
      THEN ROUND(pc.dka_risk_percentile_in_gen_pop, 2)
    ELSE NULL
  END AS risk_score_percentile_vs_general
FROM group_stats AS gs, percentile_calc AS pc
ORDER BY
  gs.cohort DESC;