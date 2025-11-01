WITH eligible_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 71 AND 81
    AND d.icd_code LIKE 'K85%'
    AND d.icd_version = 10
),
medication_complexity AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    COALESCE(COUNT(DISTINCT pr.drug), 0) AS complexity_score
  FROM eligible_patients e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON e.hadm_id = pr.hadm_id
    AND pr.starttime BETWEEN e.admittime AND e.admittime + INTERVAL 72 HOUR
  GROUP BY e.subject_id, e.hadm_id
),
tertiles AS (
  SELECT
    mc.*,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM medication_complexity mc
),
outcomes AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    t.complexity_score,
    t.tertile,
    e.admittime,
    e.dischtime,
    e.hospital_expire_flag,
    TIMESTAMP_DIFF(e.dischtime, e.admittime, DAY) AS los,
    e.hospital_expire_flag AS in_hospital_mortality,
    -- Check for readmission within 30 days using LEFT JOIN
    MAX(CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS readmitted_30d
  FROM tertiles t
  INNER JOIN eligible_patients e
    ON t.subject_id = e.subject_id AND t.hadm_id = e.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON e.subject_id = a2.subject_id
    AND a2.admittime > e.dischtime
    AND a2.admittime <= e.dischtime + INTERVAL 30 DAY
  GROUP BY t.subject_id, t.hadm_id, t.complexity_score, t.tertile, e.admittime, e.dischtime, e.hospital_expire_flag
),
final AS (
  SELECT
    tertile,
    AVG(los) AS avg_los,
    AVG(in_hospital_mortality) AS in_hospital_mortality_rate,
    AVG(readmitted_30d) AS readmission_rate_30d
  FROM outcomes
  GROUP BY tertile
)
SELECT * FROM final;