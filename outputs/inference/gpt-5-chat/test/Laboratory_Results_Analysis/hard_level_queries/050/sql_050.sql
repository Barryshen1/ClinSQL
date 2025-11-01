WITH ards_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND (
      (d.icd_version = 10 AND d.icd_code = 'J80') OR
      (d.icd_version = 9 AND d.icd_code = '51882')
    )
),
lab_scores AS (
  SELECT ap.subject_id, ap.hadm_id,
    COUNTIF(LOWER(le.flag) = 'abnormal' OR LOWER(le.flag) = 'critical') AS instability_score
  FROM ards_patients ap
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ap.subject_id = le.subject_id AND ap.hadm_id = le.hadm_id
   AND le.charttime BETWEEN ap.admittime AND DATETIME_ADD(ap.admittime, INTERVAL 72 HOUR)
  GROUP BY ap.subject_id, ap.hadm_id
),
score_threshold AS (
  SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75_score
  FROM lab_scores
),
high_instability AS (
  SELECT ls.subject_id, ls.hadm_id, ls.instability_score,
         ap.hospital_expire_flag, ap.los_days
  FROM lab_scores ls
  JOIN ards_patients ap
    ON ls.subject_id = ap.subject_id AND ls.hadm_id = ap.hadm_id
  CROSS JOIN score_threshold st
  WHERE ls.instability_score >= st.p75_score
),
non_ards_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.hadm_id NOT IN (
      SELECT hadm_id FROM ards_patients
    )
),
non_ards_lab_scores AS (
  SELECT nap.subject_id, nap.hadm_id,
    COUNTIF(LOWER(le.flag) = 'abnormal' OR LOWER(le.flag) = 'critical') AS instability_score
  FROM non_ards_patients nap
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON nap.subject_id = le.subject_id AND nap.hadm_id = le.hadm_id
   AND le.charttime BETWEEN nap.admittime AND DATETIME_ADD(nap.admittime, INTERVAL 72 HOUR)
  GROUP BY nap.subject_id, nap.hadm_id
)
SELECT
  MAX(st.p75_score) AS instability_score_75th_percentile,
  AVG(CAST(hi.hospital_expire_flag AS FLOAT64)) AS mortality_rate_high_instability_ards,
  AVG(hi.los_days) AS mean_los_days_high_instability_ards,
  AVG(hi.instability_score) AS mean_instability_score_high_instability_ards,
  AVG(nal.instability_score) AS mean_instability_score_non_ards
FROM score_threshold st
JOIN high_instability hi ON TRUE
JOIN non_ards_lab_scores nal ON TRUE;