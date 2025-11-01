WITH 
cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 84 AND 94
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'N17%'
    )
),

med_complex AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT drug) AS med_count
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE hadm_id IN (SELECT hadm_id FROM cohort)
  GROUP BY hadm_id
),

quintiles AS (
  SELECT 
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    m.med_count,
    NTILE(5) OVER (ORDER BY m.med_count) AS quintile
  FROM cohort c
  INNER JOIN med_complex m
    ON c.hadm_id = m.hadm_id
),

readmission_flag AS (
  SELECT 
    q.hadm_id,
    CASE 
      WHEN LEAD(q.admittime) OVER (
        PARTITION BY q.subject_id 
        ORDER BY q.admittime
      ) <= TIMESTAMP_ADD(q.dischtime, INTERVAL 30 DAY) 
      THEN 1 ELSE 0 
    END AS readmission_30d
  FROM quintiles q
),

coadmin AS (
  SELECT 
    p.hadm_id,
    MAX(CASE WHEN LOWER(p.drug) IN (
      'warfarin', 'heparin', 'enoxaparin', 'rivaroxaban', 'apixaban'
    ) THEN 1 ELSE 0 END) AS has_anticoagulant,
    MAX(CASE WHEN LOWER(p.drug) IN (
      'morphine', 'fentanyl', 'hydromorphone', 'oxycodone'
    ) THEN 1 ELSE 0 END) AS has_opioid
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE p.hadm_id IN (SELECT hadm_id FROM quintiles)
  GROUP BY p.hadm_id
),

coadmin_final AS (
  SELECT 
    hadm_id,
    CASE WHEN has_anticoagulant = 1 AND has_opioid = 1 THEN 1 ELSE 0 END AS coadmin_flag
  FROM coadmin
)

SELECT
  q.quintile,
  AVG(DATETIME_DIFF(q.dischtime, q.admittime, HOUR) / 24.0) AS avg_los,
  AVG(q.hospital_expire_flag) * 100 AS mortality_pct,
  AVG(r.readmission_30d) * 100 AS readmission_30d_pct,
  SUM(c.coadmin_flag) AS anticoagulant_opioid_coadmin_count
FROM quintiles q
LEFT JOIN readmission_flag r ON q.hadm_id = r.hadm_id
LEFT JOIN coadmin_final c ON q.hadm_id = c.hadm_id
GROUP BY q.quintile
ORDER BY q.quintile;