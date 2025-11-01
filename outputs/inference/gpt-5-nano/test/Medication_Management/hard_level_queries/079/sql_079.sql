WITH hemorrhagic_cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id
   AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE di.icd_version = 10
    AND di.icd_code LIKE 'I6%'
    AND p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 89 AND 99
),
med_count AS (
  SELECT
    h.hadm_id,
    COUNT(DISTINCT sp.drug) AS unique_drug_count
  FROM hemorrhagic_cohort AS h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS sp
    ON sp.subject_id = h.subject_id
   AND sp.hadm_id = h.hadm_id
   AND sp.starttime >= h.admittime
   AND sp.starttime < TIMESTAMP_ADD(h.admittime, INTERVAL 7 DAY)
  WHERE sp.drug IS NOT NULL
  GROUP BY h.hadm_id
),
cohort AS (
  SELECT
    h.hadm_id,
    h.subject_id,
    h.admittime,
    h.dischtime,
    h.hospital_expire_flag,
    h.deathtime,
    COALESCE(m.unique_drug_count, 0) AS unique_drug_count
  FROM hemorrhagic_cohort AS h
  LEFT JOIN med_count AS m ON m.hadm_id = h.hadm_id
),
quint AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    deathtime,
    unique_drug_count,
    NTILE(5) OVER (ORDER BY unique_drug_count ASC) AS quintile
  FROM cohort
)

SELECT
  quintile,
  AVG(los_days) AS avg_los_days,
  AVG(inpatient_mortality) AS inpatient_mortality_rate,
  AVG(readmission_30d) AS readmission_30d_rate
FROM (
  SELECT
    q.quintile,
    TIMESTAMP_DIFF(TIMESTAMP(c.dischtime), TIMESTAMP(c.admittime), SECOND) / 86400.0 AS los_days,
    CASE WHEN c.hospital_expire_flag = 1 OR c.deathtime IS NOT NULL THEN 1.0 ELSE 0.0 END AS inpatient_mortality,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = c.subject_id
          AND a2.hadm_id != c.hadm_id
          AND a2.admittime > c.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
      ) THEN 1.0
      ELSE 0.0
    END AS readmission_30d
  FROM quint q
  JOIN cohort c ON c.hadm_id = q.hadm_id
) t
GROUP BY quintile
ORDER BY quintile;