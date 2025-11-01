WITH base_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  WHERE LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 64 AND 74
    AND LOWER(ddi.long_title) LIKE '%pulmonary embolism%'
    AND a.dischtime IS NOT NULL
),

meds_24h AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.deathtime,
    b.hospital_expire_flag,
    TIMESTAMP_DIFF(b.dischtime, b.admittime, SECOND) / 86400.0 AS los_days,
    CASE WHEN b.deathtime IS NOT NULL OR b.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mortality,
    COUNT(DISTINCT pr.drug) AS med_count
  FROM base_admissions AS b
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.subject_id = b.subject_id
   AND pr.hadm_id = b.hadm_id
   AND pr.starttime >= b.admittime
   AND pr.starttime < TIMESTAMP_ADD(b.admittime, INTERVAL 24 HOUR)
  GROUP BY
    b.subject_id,
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.deathtime,
    b.hospital_expire_flag
),

tertiles AS (
  SELECT
    m.*,
    NTILE(3) OVER (ORDER BY m.med_count) AS med_tertile
  FROM meds_24h AS m
),

with_next AS (
  SELECT
    t.*,
    LEAD(t.admittime) OVER (PARTITION BY t.subject_id ORDER BY t.admittime) AS next_admit
  FROM tertiles AS t
)

SELECT
  med_tertile,
  MIN(med_count) AS med_count_min,
  MAX(med_count) AS med_count_max,
  COUNT(*) AS n_admissions,
  AVG(los_days) AS avg_los_days,
  SUM(mortality) / COUNT(*) * 100 AS mortality_percent,
  SUM(
      CASE
        WHEN next_admit IS NOT NULL
             AND next_admit <= TIMESTAMP_ADD(dischtime, INTERVAL 30 DAY)
        THEN 1 ELSE 0
      END
  ) / COUNT(*) * 100 AS readmission_30d_percent
FROM with_next
GROUP BY med_tertile
ORDER BY med_tertile;