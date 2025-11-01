WITH hemorrhagic_stroke_patients AS (
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
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432'))
      OR
      (d.icd_version = 10 AND d.icd_code IN ('I60', 'I61', 'I62'))
    )
),

medication_complexity AS (
  SELECT
    hsp.subject_id,
    hsp.hadm_id,
    COUNT(DISTINCT pr.drug) AS unique_drugs_first_7_days
  FROM hemorrhagic_stroke_patients hsp
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON hsp.hadm_id = pr.hadm_id
    AND pr.starttime >= hsp.admittime
    AND pr.starttime < TIMESTAMP_ADD(hsp.admittime, INTERVAL 7 DAY)
  GROUP BY hsp.subject_id, hsp.hadm_id
),

quintiles AS (
  SELECT
    hsp.*,
    mc.unique_drugs_first_7_days,
    NTILE(5) OVER (ORDER BY mc.unique_drugs_first_7_days) AS medication_quintile
  FROM hemorrhagic_stroke_patients hsp
  LEFT JOIN medication_complexity mc
    ON hsp.subject_id = mc.subject_id AND hsp.hadm_id = mc.hadm_id
),

readmission_flag AS (
  SELECT
    subject_id,
    hadm_id,
    dischtime,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM physionet-data.mimiciv_3_1_hosp.admissions
  WHERE subject_id IN (SELECT subject_id FROM hemorrhagic_stroke_patients)
),

final_data AS (
  SELECT
    q.*,
    TIMESTAMP_DIFF(q.dischtime, q.admittime, DAY) AS los,
    CASE
      WHEN ra.next_admittime IS NOT NULL
        AND TIMESTAMP_DIFF(ra.next_admittime, q.dischtime, DAY) <= 30
      THEN 1
      ELSE 0
    END AS thirty_day_readmission
  FROM quintiles q
  LEFT JOIN readmission_flag ra
    ON q.subject_id = ra.subject_id AND q.hadm_id = ra.hadm_id
)

SELECT
  medication_quintile,
  AVG(los) AS avg_los,
  AVG(hospital_expire_flag) AS inpatient_mortality_rate,
  AVG(thirty_day_readmission) AS thirty_day_readmission_rate
FROM final_data
GROUP BY medication_quintile
ORDER BY medication_quintile;