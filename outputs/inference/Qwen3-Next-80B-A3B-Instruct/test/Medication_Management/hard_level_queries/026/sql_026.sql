WITH pneumonia_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND (
      LOWER(did.long_title) LIKE '%pneumonia%'
      OR d.icd_code BETWEEN '480' AND '486'  -- ICD-9
      OR (d.icd_version = 10 AND d.icd_code LIKE 'J1%')  -- ICD-10: J12-J18
    )
),

medication_complexity AS (
  SELECT
    pa.hadm_id,
    COUNT(DISTINCT pr.drug) AS unique_drugs_7days
  FROM pneumonia_admissions pa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pa.hadm_id = pr.hadm_id
    AND pr.starttime >= pa.admittime
    AND pr.starttime < TIMESTAMP_ADD(pa.admittime, INTERVAL 7 DAY)
  GROUP BY pa.hadm_id
),

tertiles AS (
  SELECT
    mc.hadm_id,
    mc.unique_drugs_7days,
    NTILE(3) OVER (ORDER BY mc.unique_drugs_7days) AS medication_tertile
  FROM medication_complexity mc
),

readmission_flag AS (
  SELECT
    pa.hadm_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = pa.subject_id
          AND a2.hadm_id != pa.hadm_id
          AND a2.admittime > pa.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(pa.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmission_30day
  FROM pneumonia_admissions pa
)

SELECT
  t.medication_tertile,
  COUNT(*) AS admission_count,
  MIN(t.unique_drugs_7days) AS min_unique_drugs,
  AVG(t.unique_drugs_7days) AS avg_unique_drugs,
  MAX(t.unique_drugs_7days) AS max_unique_drugs,
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS mean_los_days,
  AVG(a.hospital_expire_flag) * 100 AS in_hospital_mortality_pct,
  AVG(r.readmission_30day) * 100 AS thirty_day_readmission_pct
FROM tertiles t
JOIN pneumonia_admissions a ON t.hadm_id = a.hadm_id
JOIN readmission_flag r ON t.hadm_id = r.hadm_id
GROUP BY t.medication_tertile
ORDER BY t.medication_tertile;