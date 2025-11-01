WITH hhs_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.subject_id = a.subject_id
   AND i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON di.icd_code = ddi.icd_code
   AND di.icd_version = ddi.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND LOWER(ddi.long_title) LIKE '%hyperosmolar%'  -- broad capture of HHS
),
proc_burden AS (
  SELECT
    hc.subject_id,
    hc.hadm_id,
    hc.stay_id,
    COUNT(pe.itemid) AS procedures_count,
    hc.admittime,
    hc.dischtime,
    hc.hospital_expire_flag,
    hc.intime,
    hc.outtime
  FROM hhs_cohort hc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON hc.subject_id = pe.subject_id
   AND hc.stay_id = pe.stay_id
   AND TIMESTAMP_DIFF(pe.starttime, hc.intime, HOUR) >= 0
   AND TIMESTAMP_DIFF(pe.starttime, hc.intime, HOUR) <= 48
  GROUP BY hc.subject_id, hc.hadm_id, hc.stay_id, hc.admittime, hc.dischtime, hc.hospital_expire_flag, hc.intime, hc.outtime
),
proc_with_quintile AS (
  SELECT *,
         NTILE(5) OVER (ORDER BY procedures_count) AS quintile
  FROM proc_burden
),
readmit_flags AS (
  SELECT
    base.subject_id,
    base.hadm_id,
    CASE WHEN MIN(DATE_DIFF(next.admittime, base.dischtime, DAY)) <= 30
              AND MIN(DATE_DIFF(next.admittime, base.dischtime, DAY)) > 0
         THEN 1 ELSE 0 END AS readmit_30d_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` base
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next
    ON base.subject_id = next.subject_id
   AND base.hadm_id != next.hadm_id
   AND next.admittime > base.dischtime
   AND DATE_DIFF(next.admittime, base.dischtime, DAY) <= 30
  GROUP BY base.subject_id, base.hadm_id
)
SELECT
  quintile,
  COUNT(*) AS num_icu_stays,
  ROUND(AVG(procedures_count),2) AS mean_procedures,
  MIN(procedures_count) AS min_procedures,
  MAX(procedures_count) AS max_procedures,
  ROUND(100 * AVG(hospital_expire_flag),2) AS hospital_mortality_pct,
  ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)),2) AS mean_hosp_los_days,
  ROUND(100 * AVG(IF(r.readmit_30d_flag = 1, 1, 0)),2) AS readmit_30day_pct
FROM proc_with_quintile pw
LEFT JOIN readmit_flags r
  ON pw.subject_id = r.subject_id
 AND pw.hadm_id = r.hadm_id
GROUP BY quintile
ORDER BY quintile;