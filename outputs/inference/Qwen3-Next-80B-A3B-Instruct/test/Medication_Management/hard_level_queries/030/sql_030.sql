WITH eligible_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND LOWER(d_icd.long_title) LIKE '%acute pancreatitis%'
    AND d.icd_version = 10
),

medication_complexity AS (
  SELECT
    ea.subject_id,
    ea.hadm_id,
    ea.admittime,
    ea.dischtime,
    ea.hospital_expire_flag,
    COUNT(DISTINCT p.drug) AS med_complexity_score
  FROM eligible_admissions ea
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON ea.hadm_id = p.hadm_id
    AND p.starttime >= ea.admittime
    AND p.starttime <= ea.admittime + INTERVAL '72' HOUR
  GROUP BY ea.subject_id, ea.hadm_id, ea.admittime, ea.dischtime, ea.hospital_expire_flag
),

tertiles AS (
  SELECT *,
    NTILE(3) OVER (ORDER BY med_complexity_score) AS complexity_tertile
  FROM medication_complexity
),

readmission_flag AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    t.med_complexity_score,
    t.complexity_tertile,
    t.admittime,
    t.dischtime,
    t.hospital_expire_flag,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = t.subject_id
          AND a2.hadm_id != t.hadm_id
          AND a2.admittime > t.dischtime
          AND a2.admittime <= t.dischtime + INTERVAL '30' DAY
      ) THEN 1
      ELSE 0
    END AS readmission_30d_flag
  FROM tertiles t
)

SELECT
  complexity_tertile,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
  AVG(readmission_30d_flag) AS thirty_day_readmission_rate,
  COUNT(*) AS n_patients
FROM readmission_flag
GROUP BY complexity_tertile
ORDER BY complexity_tertile;