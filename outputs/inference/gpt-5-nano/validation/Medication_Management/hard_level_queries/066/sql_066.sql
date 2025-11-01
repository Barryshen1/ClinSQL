WITH transplant_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON pat.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dic
    ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
  WHERE LOWER(pat.gender) = 'male'
    AND pat.anchor_age BETWEEN 43 AND 53
    AND LOWER(dic.long_title) LIKE '%transplant%'
),
mcs_per_admission AS (
  SELECT
    tc.subject_id,
    tc.hadm_id,
    COALESCE(SUM(
      1.0
      +
      CASE
        -- route_weight: infusion routes typically more complex
        WHEN LOWER(rx.route) LIKE '%iv%' OR LOWER(rx.route) LIKE '%intravenous%' THEN 2.0
        WHEN LOWER(rx.route) LIKE '%im%' THEN 1.25
        WHEN LOWER(rx.route) LIKE '%injection%' THEN 1.3
        WHEN LOWER(rx.route) LIKE '%oral%' THEN 1.0
        WHEN LOWER(rx.route) LIKE '%po%' THEN 1.0
        ELSE 1.0
      END
      +
      COALESCE(
        CASE
          WHEN CAST(rx.doses_per_24_hrs AS FLOAT64) >= 5 THEN 2.0
          WHEN CAST(rx.doses_per_24_hrs AS FLOAT64) >= 3 THEN 1.0
          WHEN CAST(rx.doses_per_24_hrs AS FLOAT64) >= 2 THEN 0.5
          ELSE 0.0
        END, 0.0)
    ), 0.0) AS mcs_score
  FROM transplant_cohort tc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS rx
    ON rx.subject_id = tc.subject_id
   AND rx.hadm_id = tc.hadm_id
   AND rx.starttime >= tc.admittime
   AND rx.starttime < TIMESTAMP_ADD(tc.admittime, INTERVAL 7 DAY)
  GROUP BY tc.subject_id, tc.hadm_id
),
admission_mcs AS (
  SELECT
    tc.subject_id,
    tc.hadm_id,
    tc.admittime,
    tc.dischtime,
    tc.hospital_expire_flag,
    tc.los_days,
    COALESCE(m.mcs_score, 0.0) AS mcs_score
  FROM transplant_cohort tc
  LEFT JOIN mcs_per_admission m
    ON m.subject_id = tc.subject_id
   AND m.hadm_id = tc.hadm_id
),
ordered AS (
  SELECT
    am.*,
    LEAD(am.admittime) OVER (PARTITION BY am.subject_id ORDER BY am.admittime) AS next_admittime
  FROM admission_mcs am
),
readmit AS (
  SELECT
    o.*,
    CASE
      WHEN next_admittime IS NOT NULL
           AND TIMESTAMP_DIFF(next_admittime, dischtime, DAY) <= 30 THEN 1
      ELSE 0
    END AS readmit_30
  FROM ordered o
),
quart AS (
  SELECT r.*,
         NTILE(4) OVER (ORDER BY mcs_score) AS quartile
  FROM readmit r
)
SELECT
  quartile,
  COUNT(*) AS n,
  AVG(mcs_score) AS mean_mcs,
  AVG(los_days) AS mean_los,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS in_hospital_mortality,
  AVG(readmit_30) AS readmission_30_day_rate
FROM quart
GROUP BY quartile
ORDER BY quartile;