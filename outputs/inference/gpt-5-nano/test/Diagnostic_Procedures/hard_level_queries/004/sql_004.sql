WITH
  -- Identify admissions with intracranial hemorrhage (ICH) across ICD versions
  ich_admissions AS (
    SELECT DISTINCT d.subject_id, d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
      ON d.icd_code = di.icd_code
     AND d.icd_version = di.icd_version
    WHERE di.long_title LIKE '%intracranial hemorrhage%'
       OR di.long_title LIKE '%intracerebral hemorrhage%'
  ),
  -- Cohort: female, aged 50-60, with documented ICH
  cohort_stays AS (
    SELECT s.subject_id, s.hadm_id, s.stay_id, s.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
    JOIN ich_admissions AS i
      ON s.subject_id = i.subject_id
     AND s.hadm_id = i.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON s.subject_id = p.subject_id
    WHERE p.gender = 'Female'
      AND p.anchor_age BETWEEN 50 AND 60
  ),
  -- Procedure burden within first 72 ICU hours per stay
  burden AS (
    SELECT c.stay_id, COUNT(pe.starttime) AS proc_burden_72h
    FROM cohort_stays AS c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
      ON pe.stay_id = c.stay_id
     AND pe.starttime BETWEEN c.intime
                        AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
    GROUP BY c.stay_id
  ),
  -- LOS and mortality data for subgroup (ICH female 50-60)
  subgroup_los_mort AS (
    SELECT i.los AS los_days, a.hospital_expire_flag AS died
    FROM cohort_stays AS c
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
      ON c.stay_id = i.stay_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON i.hadm_id = a.hadm_id
  ),
  -- LOS and mortality data for general ICU (all stays)
  general_los_mort AS (
    SELECT i.los AS los_days, a.hospital_expire_flag AS died
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON i.hadm_id = a.hadm_id
  ),
  -- Percentiles for procedure burden (subset: 50-60y female ICH)
  proc_percentiles AS (
    SELECT
      PERCENTILE_CONT(proc_burden_72h, 0.25) OVER() AS p25_proc_burden,
      PERCENTILE_CONT(proc_burden_72h, 0.50) OVER() AS median_proc_burden,
      PERCENTILE_CONT(proc_burden_72h, 0.90) OVER() AS p90_proc_burden
    FROM burden
    LIMIT 1
  ),
  -- Subgroup metrics: LOS percentiles + mortality for the 50-60 y female ICH subgroup
  subgroup_metrics AS (
    SELECT
      PERCENTILE_CONT(los_days, 0.25) OVER() AS los_subgroup_p25,
      PERCENTILE_CONT(los_days, 0.50) OVER() AS los_subgroup_median,
      PERCENTILE_CONT(los_days, 0.90) OVER() AS los_subgroup_p90,
      AVG(died) AS mortality_subgroup
    FROM subgroup_los_mort
    LIMIT 1
  ),
  -- General ICU metrics: LOS percentiles + mortality for all ICU stays
  general_metrics AS (
    SELECT
      PERCENTILE_CONT(los_days, 0.25) OVER() AS los_all_p25,
      PERCENTILE_CONT(los_days, 0.50) OVER() AS los_all_median,
      PERCENTILE_CONT(los_days, 0.90) OVER() AS los_all_p90,
      AVG(died) AS mortality_all
    FROM general_los_mort
    LIMIT 1
  )
SELECT
  p25_proc_burden,
  median_proc_burden,
  p90_proc_burden,
  los_subgroup_p25,
  los_subgroup_median,
  los_subgroup_p90,
  mortality_subgroup,
  los_all_p25,
  los_all_median,
  los_all_p90,
  mortality_all
FROM proc_percentiles
CROSS JOIN subgroup_metrics
CROSS JOIN general_metrics;