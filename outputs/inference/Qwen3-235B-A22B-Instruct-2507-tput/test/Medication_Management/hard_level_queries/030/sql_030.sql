WITH pancreatitis_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%acute pancreatitis%'
    AND icd_version = 10
),
eligible_admissions AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         p.anchor_age, p.anchor_year, p.gender,
         DATETIME_ADD(a.admittime, INTERVAL 72 HOUR) AS end_window
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 71 AND 81
    AND a.hadm_id IN (
      SELECT DISTINCT di.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN pancreatitis_codes pc ON di.icd_code = pc.icd_code AND di.icd_version = 10
    )
),
medication_complexity AS (
  SELECT ea.hadm_id,
         COUNT(DISTINCT pr.drug) AS medication_count
  FROM eligible_admissions ea
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON ea.hadm_id = pr.hadm_id
    AND pr.starttime >= ea.admittime
    AND pr.starttime <= ea.end_window
  GROUP BY ea.hadm_id
),
tertiles AS (
  SELECT ea.hadm_id,
         ea.subject_id,
         ea.admittime, ea.dischtime, ea.hospital_expire_flag,
         mc.medication_count,
         NTILE(3) OVER (ORDER BY mc.medication_count) AS tertile
  FROM eligible_admissions ea
  JOIN medication_complexity mc ON ea.hadm_id = mc.hadm_id
),
readmissions AS (
  SELECT t.*,
         LEAD(t.admittime) OVER (PARTITION BY t.subject_id ORDER BY t.admittime) AS next_admittime
  FROM tertiles t
),
outcomes AS (
  SELECT tertile,
         AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days,
         AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
         AVG(CASE WHEN next_admittime IS NOT NULL 
                   AND DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30 
                   THEN 1 ELSE 0 END) AS readmission_30day_rate
  FROM readmissions
  GROUP BY tertile
)
SELECT tertile,
       ROUND(avg_los_days, 2) AS avg_los_days,
       ROUND(in_hospital_mortality_rate, 3) AS in_hospital_mortality_rate,
       ROUND(readmission_30day_rate, 3) AS readmission_30day_rate
FROM outcomes
ORDER BY tertile;