WITH target_cohort AS (
  SELECT DISTINCT
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON i.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND (
      LOWER(dicd.long_title) LIKE '%intracranial hemorrhage%'
      OR d.icd_code IN ('430','431','432.9','I60','I61','I62')
    )
),
general_cohort AS (
  SELECT DISTINCT
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
),
target_procedures AS (
  SELECT
    tc.stay_id,
    COUNT(pe.itemid) AS proc_count
  FROM target_cohort tc
  LEFT JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON tc.stay_id = pe.stay_id
    AND pe.starttime >= tc.intime
    AND pe.starttime <= TIMESTAMP_ADD(tc.intime, INTERVAL 72 HOUR)
    AND pe.starttime IS NOT NULL
  GROUP BY tc.stay_id
),
general_procedures AS (
  SELECT
    gc.stay_id,
    COUNT(pe.itemid) AS proc_count
  FROM general_cohort gc
  LEFT JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON gc.stay_id = pe.stay_id
    AND pe.starttime >= gc.intime
    AND pe.starttime <= TIMESTAMP_ADD(gc.intime, INTERVAL 72 HOUR)
    AND pe.starttime IS NOT NULL
  GROUP BY gc.stay_id
),
target_summary AS (
  SELECT
    'Target Cohort (F, 50-60, ICH)' AS cohort,
    PERCENTILE_DISC(tp.proc_count, 0.25) AS proc_25th,
    PERCENTILE_DISC(tp.proc_count, 0.50) AS proc_median,
    PERCENTILE_DISC(tp.proc_count, 0.90) AS proc_90th,
    PERCENTILE_DISC(tc.los, 0.25) AS los_25th,
    PERCENTILE_DISC(tc.los, 0.50) AS los_median,
    PERCENTILE_DISC(tc.los, 0.90) AS los_90th,
    AVG(tc.hospital_expire_flag) AS mortality_rate
  FROM target_cohort tc
  LEFT JOIN target_procedures tp ON tc.stay_id = tp.stay_id
),
general_summary AS (
  SELECT
    'General ICU Cohort' AS cohort,
    PERCENTILE_DISC(gp.proc_count, 0.25) AS proc_25th,
    PERCENTILE_DISC(gp.proc_count, 0.50) AS proc_median,
    PERCENTILE_DISC(gp.proc_count, 0.90) AS proc_90th,
    PERCENTILE_DISC(gc.los, 0.25) AS los_25th,
    PERCENTILE_DISC(gc.los, 0.50) AS los_median,
    PERCENTILE_DISC(gc.los, 0.90) AS los_90th,
    AVG(gc.hospital_expire_flag) AS mortality_rate
  FROM general_cohort gc
  LEFT JOIN general_procedures gp ON gc.stay_id = gp.stay_id
)
SELECT * FROM target_summary
UNION ALL
SELECT * FROM general_summary;