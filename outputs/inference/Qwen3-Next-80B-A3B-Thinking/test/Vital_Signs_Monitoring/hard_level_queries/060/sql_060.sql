WITH icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) AS age_at_intime,
    a.deathtime,
    CASE WHEN h.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_hhs
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  LEFT JOIN (
    SELECT
      d.subject_id,
      d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
      ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    WHERE di.long_title LIKE '%hyperosmolar%' OR di.long_title LIKE '%HHS%'
  ) h
    ON i.subject_id = h.subject_id AND i.hadm_id = h.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 78 AND 88
),

abnormal_vitals AS (
  SELECT
    i.stay_id,
    COUNT(*) AS abnormal_count
  FROM icu_stays i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE c.charttime BETWEEN i.intime AND i.intime + INTERVAL 48 HOUR
    AND d.lownormalvalue IS NOT NULL
    AND d.highnormalvalue IS NOT NULL
    AND (c.valuenum < d.lownormalvalue OR c.valuenum > d.highnormalvalue)
  GROUP BY i.stay_id
),

los_data AS (
  SELECT
    i.stay_id,
    DATETIME_DIFF(i.outtime, i.intime, HOUR) AS total_los,
    CASE WHEN i.deathtime IS NOT NULL AND i.deathtime <= i.intime + INTERVAL 48 HOUR THEN 1 ELSE 0 END AS mortality_48h
  FROM icu_stays i
)

SELECT
  is_hhs,
  PERCENTILE_CONT(abnormal_count, 0.25) WITHIN GROUP (ORDER BY abnormal_count) AS p25_abnormal,
  PERCENTILE_CONT(abnormal_count, 0.5) WITHIN GROUP (ORDER BY abnormal_count) AS median_abnormal,
  PERCENTILE_CONT(abnormal_count, 0.75) WITHIN GROUP (ORDER BY abnormal_count) AS p75_abnormal,
  PERCENTILE_CONT(total_los, 0.25) WITHIN GROUP (ORDER BY total_los) AS p25_los,
  PERCENTILE_CONT(total_los, 0.5) WITHIN GROUP (ORDER BY total_los) AS median_los,
  PERCENTILE_CONT(total_los, 0.75) WITHIN GROUP (ORDER BY total_los) AS p75_los,
  PERCENTILE_CONT(mortality_48h, 0.25) WITHIN GROUP (ORDER BY mortality_48h) AS p25_mortality,
  PERCENTILE_CONT(mortality_48h, 0.5) WITHIN GROUP (ORDER BY mortality_48h) AS median_mortality,
  PERCENTILE_CONT(mortality_48h, 0.75) WITHIN GROUP (ORDER BY mortality_48h) AS p75_mortality
FROM icu_stays i
LEFT JOIN abnormal_vitals av ON i.stay_id = av.stay_id
LEFT JOIN los_data ld ON i.stay_id = ld.stay_id
GROUP BY is_hhs;