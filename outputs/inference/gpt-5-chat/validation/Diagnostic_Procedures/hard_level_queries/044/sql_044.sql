WITH cardiogenic_shock_patients AS (
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.subject_id = adm.subject_id
    AND icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.subject_id = dx.subject_id
    AND icu.hadm_id = dx.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 82 AND 92
    AND (
      (dx.icd_version = 9 AND dx.icd_code = '78551') OR
      (dx.icd_version = 10 AND dx.icd_code = 'R570')
    )
),
procedure_counts AS (
  SELECT
    csp.subject_id,
    csp.hadm_id,
    csp.stay_id,
    csp.intime,
    COUNT(pe.itemid) AS procedure_count
  FROM cardiogenic_shock_patients csp
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON csp.stay_id = pe.stay_id
    AND pe.starttime >= csp.intime
    AND pe.starttime < TIMESTAMP_ADD(csp.intime, INTERVAL 24 HOUR)
  GROUP BY csp.subject_id, csp.hadm_id, csp.stay_id, csp.intime
),
quintiled AS (
  SELECT
    pc.*,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    NTILE(5) OVER (ORDER BY pc.procedure_count) AS proc_quintile
  FROM procedure_counts pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pc.subject_id = adm.subject_id AND pc.hadm_id = adm.hadm_id
)
SELECT
  proc_quintile,
  ROUND(AVG(procedure_count),2) AS mean_procedure_count,
  ROUND(AVG(DATETIME_DIFF(adm_dischtime, adm_admittime, DAY)),2) AS mean_hosp_los_days,
  ROUND(AVG(hospital_expire_flag)*100,2) AS in_hosp_mortality_pct
FROM (
  SELECT
    proc_quintile,
    procedure_count,
    DATETIME(admittime) AS adm_admittime,
    DATETIME(dischtime) AS adm_dischtime,
    hospital_expire_flag
  FROM quintiled
) sub
GROUP BY proc_quintile
ORDER BY proc_quintile;