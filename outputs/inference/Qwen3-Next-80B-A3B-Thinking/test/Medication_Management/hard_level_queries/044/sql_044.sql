WITH pe_population AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON d.icd_code = d_diag.icd_code AND d.icd_version = d_diag.icd_version
  WHERE d_diag.long_title LIKE '%pulmonary embolism%'
    AND p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 64 AND 74
),

med_counts AS (
  SELECT
    p.hadm_id,
    COUNT(DISTINCT pr.drug) AS distinct_meds
  FROM pe_population p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.hadm_id = pr.hadm_id
    AND pr.starttime BETWEEN p.admittime AND p.admittime + INTERVAL '24 hours'
  GROUP BY p.hadm_id
),

readmission AS (
  SELECT
    a.hadm_id,
    MAX(CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS readmitted
  FROM pe_population a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a.subject_id = a2.subject_id
    AND a2.admittime > a.dischtime
    AND a2.admittime <= a.dischtime + INTERVAL '30 days'
  GROUP BY a.hadm_id
),

tertiles AS (
  SELECT
    hadm_id,
    distinct_meds,
    NTILE(3) OVER (ORDER BY distinct_meds) AS tertile
  FROM med_counts
)

SELECT
  t.tertile,
  COUNT(t.hadm_id) AS admissions,
  MIN(t.distinct_meds) AS min_meds,
  MAX(t.distinct_meds) AS max_meds,
  AVG(p.dischtime - p.admittime) AS avg_los_days,
  AVG(CAST(p.hospital_expire_flag AS FLOAT64)) * 100 AS mortality_percent,
  AVG(r.readmitted) * 100 AS readmission_percent_30days
FROM tertiles t
JOIN pe_population p ON t.hadm_id = p.hadm_id
LEFT JOIN readmission r ON t.hadm_id = r.hadm_id
GROUP BY t.tertile
ORDER BY t.tertile;