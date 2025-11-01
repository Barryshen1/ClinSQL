WITH cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id,
         adm.admittime, adm.dischtime, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.subject_id = dx.subject_id AND adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
    ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 70 AND 80
    AND (
         (dx.icd_version = 9 AND (
            dx.icd_code LIKE '430%' OR
            dx.icd_code LIKE '431%' OR
            dx.icd_code LIKE '432%' ))
         OR (dx.icd_version = 10 AND (
            dx.icd_code LIKE 'I60%' OR
            dx.icd_code LIKE 'I61%' OR
            dx.icd_code LIKE 'I62%' ))
        )
),
labs_48h AS (
  SELECT le.hadm_id,
         COUNTIF(flag IS NOT NULL AND LOWER(flag) IN ('abnormal', 'critical')) AS critical_lab_events
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON le.hadm_id = adm.hadm_id
  WHERE le.charttime BETWEEN adm.admittime AND TIMESTAMP_ADD(adm.admittime, INTERVAL 48 HOUR)
  GROUP BY le.hadm_id
),
cohort_with_labs AS (
  SELECT c.subject_id, c.hadm_id,
         COALESCE(l.critical_lab_events, 0) AS instability_score,
         TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days,
         c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN labs_48h l
    ON c.hadm_id = l.hadm_id
),
general_pop AS (
  SELECT adm.hadm_id,
         COALESCE(l.critical_lab_events, 0) AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  LEFT JOIN labs_48h l
    ON adm.hadm_id = l.hadm_id
)
SELECT
  APPROX_QUANTILES(instability_score, 100)[OFFSET(25)] AS cohort_p25_instability_score,
  AVG(instability_score) AS cohort_mean_instability_score,
  AVG(los_days) AS cohort_mean_los,
  AVG(hospital_expire_flag) AS cohort_in_hosp_mortality_rate,
  (SELECT AVG(instability_score) FROM general_pop) AS general_mean_instability_score
FROM cohort_with_labs;