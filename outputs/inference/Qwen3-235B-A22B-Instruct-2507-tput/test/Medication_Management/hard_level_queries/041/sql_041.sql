WITH patient_age AS (
  SELECT
    p.subject_id,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_ADD(a.dischtime, INTERVAL 30 DAY) AS followup_30d
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 40 AND 50
),

hf_admissions AS (
  SELECT DISTINCT
    pa.*
  FROM
    patient_age pa
  JOIN
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  ON
    pa.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%heart failure%'
),

med_complexity AS (
  SELECT
    h.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_count_7d
  FROM
    hf_admissions h
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
  ON
    h.hadm_id = pr.hadm_id
    AND pr.starttime >= h.admittime
    AND pr.starttime < DATETIME_ADD(h.admittime, INTERVAL 7 DAY)
  GROUP BY
    h.hadm_id
),

quintiles AS (
  SELECT
    h.*,
    COALESCE(m.med_count_7d, 0) AS med_count_7d,
    NTILE(5) OVER (ORDER BY COALESCE(m.med_count_7d, 0)) AS quintile
  FROM
    hf_admissions h
  LEFT JOIN
    med_complexity m
  ON
    h.hadm_id = m.hadm_id
),

readmissions AS (
  SELECT
    q.*,
    CASE
      WHEN LEAD(q.admittime) OVER (PARTITION BY q.subject_id ORDER BY q.admittime) <= q.followup_30d THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM
    quintiles q
),

summary_stats AS (
  SELECT
    quintile,
    COUNT(*) AS patient_count,
    MIN(med_count_7d) AS score_min,
    MAX(med_count_7d) AS score_max,
    AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
    AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
    AVG(readmitted_30d) AS readmission_30d_rate
  FROM
    readmissions
  GROUP BY
    quintile
  ORDER BY
    quintile
)

SELECT
  quintile,
  patient_count,
  CONCAT(CAST(score_min AS STRING), ' - ', CAST(score_max AS STRING)) AS score_range,
  ROUND(mean_los_days, 2) AS mean_los_days,
  ROUND(in_hospital_mortality_rate, 3) AS in_hospital_mortality,
  ROUND(readmission_30d_rate, 3) AS readmission_30d
FROM
  summary_stats;