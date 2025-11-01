WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
),

transplant_admissions AS (
  SELECT DISTINCT pa.*
  FROM patient_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON pa.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%transplant%'
),

medication_complexity AS (
  SELECT
    ta.hadm_id,
    ta.subject_id,
    ta.admittime,
    ta.dischtime,
    ta.hospital_expire_flag,
    ta.deathtime,
    COUNT(DISTINCT LOWER(RTRIM(LTRIM(drug)))) AS complexity_score
  FROM transplant_admissions ta
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON ta.hadm_id = pr.hadm_id
    AND pr.starttime IS NOT NULL
    AND pr.starttime >= ta.admittime
    AND pr.starttime < DATETIME_ADD(ta.admittime, INTERVAL 7 DAY)
  GROUP BY ta.hadm_id, ta.subject_id, ta.admittime, ta.dischtime, ta.hospital_expire_flag, ta.deathtime
),

quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY complexity_score) AS quartile
  FROM medication_complexity
),

readmission AS (
  SELECT
    q.*,
    -- Check for 30-day readmission
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = q.subject_id
          AND a2.admittime > q.dischtime
          AND a2.admittime <= DATETIME_ADD(q.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS thirty_day_readmission
  FROM quartiles q
)

SELECT
  quartile,
  COUNT(*) AS n,
  AVG(complexity_score) AS mean_score,
  AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
  AVG(thirty_day_readmission) AS thirty_day_readmission_rate
FROM readmission
GROUP BY quartile
ORDER BY quartile;