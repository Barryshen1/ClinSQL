WITH cohort AS (
  SELECT 
    icu.stay_id,
    icu.hadm_id,
    icu.intime,
    adm.hospital_expire_flag,
    -- Calculate hospital LOS in days (with decimals)
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / (24*60*60) AS hospital_los_days
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    -- Calculate age at admission
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 90 AND 100
    -- Check for sepsis diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.hadm_id = icu.hadm_id
        AND (
          (diag.icd_version = 9 AND (diag.icd_code LIKE '038%' OR diag.icd_code = '99591'))
          OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'A40%' OR diag.icd_code LIKE 'A41%' OR diag.icd_code LIKE 'R652%'))
        )
    )
),
diagnostic_counts AS (
  SELECT
    c.stay_id,
    c.hadm_id,
    c.hospital_expire_flag,
    c.hospital_los_days,
    -- Total diagnostic utilization (lab + micro events in first 24h)
    COUNT(lab.labevent_id) + COUNT(micro.microevent_id) AS diagnostic_utilization
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON c.hadm_id = lab.hadm_id
    AND lab.charttime >= c.intime
    AND lab.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` micro
    ON c.hadm_id = micro.hadm_id
    AND micro.charttime >= c.intime
    AND micro.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.stay_id, c.hadm_id, c.hospital_expire_flag, c.hospital_los_days
)
SELECT
  STDDEV(diagnostic_utilization) AS sd_diagnostic,
  APPROX_QUANTILES(diagnostic_utilization, 1000)[OFFSET(750)] AS p75_diagnostic,
  APPROX_QUANTILES(diagnostic_utilization, 1000)[OFFSET(950)] AS p95_diagnostic,
  (SUM(hospital_expire_flag) * 100.0 / COUNT(*)) AS mortality_percent,
  AVG(hospital_los_days) AS avg_los_days,
  COUNT(DISTINCT hadm_id) AS count_admissions,
  COUNT(*) AS count_icu_stays
FROM diagnostic_counts;