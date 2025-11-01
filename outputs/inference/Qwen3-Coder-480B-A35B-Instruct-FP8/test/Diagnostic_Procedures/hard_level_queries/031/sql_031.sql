WITH hhs_admissions AS (
  -- Identify admissions with HHS diagnosis
  SELECT DISTINCT
    di.subject_id,
    di.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    (d.icd_code = '2950' AND d.icd_version = 9)
    OR
    (d.icd_code = 'E1300' AND d.icd_version = 10)
),
icu_cohort AS (
  -- Filter ICU stays for male patients aged 66–76 with HHS
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    adm.hospital_expire_flag,
    adm.dischtime,
    adm.admittime,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS hospital_los
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
  ON
    icu.hadm_id = adm.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
  ON
    icu.subject_id = pat.subject_id
  JOIN
    hhs_admissions hhs
  ON
    icu.hadm_id = hhs.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 66 AND 76
),
procedures_48hr AS (
  -- Count procedures within 48 hours of ICU intime
  SELECT
    icu.stay_id,
    COUNT(proc.stay_id) AS procedure_count
  FROM
    icu_cohort icu
  LEFT JOIN
    physionet-data.mimiciv_3_1_icu.procedureevents proc
  ON
    icu.stay_id = proc.stay_id
    AND proc.starttime >= icu.intime
    AND proc.starttime <= DATETIME_ADD(icu.intime, INTERVAL 48 HOUR)
  GROUP BY
    icu.stay_id
),
readmissions AS (
  -- Compute 30-day readmission flag
  SELECT
    subject_id,
    hadm_id,
    dischtime,
    LAG(dischtime) OVER (PARTITION BY subject_id ORDER BY admittime) AS prev_dischtime,
    CASE
      WHEN LAG(dischtime) OVER (PARTITION BY subject_id ORDER BY admittime) IS NOT NULL
        AND DATETIME_DIFF(admittime, LAG(dischtime) OVER (PARTITION BY subject_id ORDER BY admittime), DAY) <= 30
      THEN 1
      ELSE 0
    END AS readmit_30_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions
),
final_cohort AS (
  -- Combine all data
  SELECT
    icu.stay_id,
    icu.hospital_expire_flag,
    icu.hospital_los,
    proc.procedure_count,
    adm.readmit_30_days
  FROM
    icu_cohort icu
  JOIN
    procedures_48hr proc
  ON
    icu.stay_id = proc.stay_id
  JOIN
    readmissions adm
  ON
    icu.hadm_id = adm.hadm_id
),
quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM
    final_cohort
)
SELECT
  quintile,
  COUNT(*) AS num_icu_stays,
  AVG(procedure_count) AS mean_procedures,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures,
  AVG(hospital_expire_flag) * 100 AS hospital_mortality_percent,
  AVG(hospital_los) AS mean_hospital_los,
  AVG(readmit_30_days) * 100 AS readmit_30_days_percent
FROM
  quintiles
GROUP BY
  quintile
ORDER BY
  quintile;