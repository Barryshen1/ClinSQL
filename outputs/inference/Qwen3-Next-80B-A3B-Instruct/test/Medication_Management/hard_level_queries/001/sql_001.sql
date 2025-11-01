WITH cardiac_arrest_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND LOWER(d_icd.long_title) LIKE '%cardiac arrest%'
),

medication_complexity AS (
  SELECT
    cap.subject_id,
    cap.hadm_id,
    COUNT(DISTINCT pr.drug) AS drug_count
  FROM cardiac_arrest_patients cap
  INNER JOIN physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON cap.hadm_id = pr.hadm_id
  WHERE pr.starttime >= cap.admittime
    AND pr.starttime < DATE_ADD(cap.admittime, INTERVAL 7 DAY)
    AND pr.starttime IS NOT NULL
  GROUP BY cap.subject_id, cap.hadm_id
),

quintiles AS (
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.drug_count,
    NTILE(5) OVER (ORDER BY mc.drug_count) AS medication_quintile
  FROM medication_complexity mc
),

readmission_30d AS (
  SELECT
    a1.subject_id,
    a1.hadm_id,
    CASE
      WHEN a2.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS readmission_30d_flag
  FROM cardiac_arrest_patients a1
  LEFT JOIN (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM physionet-data.mimiciv_3_1_hosp.admissions
  ) a2
    ON a1.subject_id = a2.subject_id
    AND a2.rn = 2
    AND a2.admittime BETWEEN a1.dischtime AND DATE_ADD(a1.dischtime, INTERVAL 30 DAY)
)

SELECT
  q.medication_quintile,
  COUNT(*) AS patient_count,
  AVG(q.drug_count) AS avg_score,
  MIN(q.drug_count) AS min_score,
  MAX(q.drug_count) AS max_score,
  AVG(TIMESTAMP_DIFF(cap.dischtime, cap.admittime, DAY)) AS avg_los,
  AVG(CAST(cap.hospital_expire_flag AS FLOAT64)) * 100 AS in_hospital_mortality_pct,
  AVG(CAST(ra.readmission_30d_flag AS FLOAT64)) * 100 AS thirty_day_readmission_pct
FROM quintiles q
INNER JOIN cardiac_arrest_patients cap
  ON q.subject_id = cap.subject_id AND q.hadm_id = cap.hadm_id
LEFT JOIN readmission_30d ra
  ON q.hadm_id = ra.hadm_id
GROUP BY q.medication_quintile
ORDER BY q.medication_quintile;