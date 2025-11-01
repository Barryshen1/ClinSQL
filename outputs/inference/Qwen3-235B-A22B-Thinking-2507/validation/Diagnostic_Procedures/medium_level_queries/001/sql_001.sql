WITH 
age_adm AS (
  SELECT 
    a.hadm_id,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),
acs_diagnoses AS (
  SELECT 
    d.hadm_id,
    MAX(CASE WHEN d.seq_num = 1 AND d.icd_code IN ('I20.0','I21.0','I21.1','I21.2','I21.3','I21.4','I21.9','I22.0','I22.1','I22.2','I22.8','I22.9','I24.0','I24.1','I24.8','I24.9') THEN 1 ELSE 0 END) AS is_primary,
    MAX(CASE WHEN d.seq_num > 1 AND d.icd_code IN ('I20.0','I21.0','I21.1','I21.2','I21.3','I21.4','I21.9','I22.0','I22.1','I22.2','I22.8','I22.9','I24.0','I24.1','I24.8','I24.9') THEN 1 ELSE 0 END) AS is_secondary
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_version = 10
  GROUP BY d.hadm_id
),
acs_admissions AS (
  SELECT 
    aa.hadm_id,
    aa.age_at_adm,
    aa.admittime,
    aa.dischtime,
    CASE 
      WHEN ad.is_primary = 1 THEN 'primary'
      WHEN ad.is_secondary = 1 THEN 'secondary'
    END AS diagnosis_type
  FROM age_adm aa
  INNER JOIN acs_diagnoses ad
    ON aa.hadm_id = ad.hadm_id
  WHERE 
    aa.age_at_adm BETWEEN 77 AND 87
    AND (ad.is_primary = 1 OR ad.is_secondary = 1)
),
los_adm AS (
  SELECT 
    hadm_id,
    diagnosis_type,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM acs_admissions
),
filtered_los AS (
  SELECT 
    hadm_id,
    diagnosis_type,
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group
  FROM los_adm
  WHERE los_days BETWEEN 1 AND 8
),
imaging_counts AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE 
    d.short_description LIKE '%X-RAY%' OR
    d.short_description LIKE '%RADIOGRAPHY%' OR
    d.short_description LIKE '%CT%' OR
    d.short_description LIKE '%COMPUTED TOMOGRAPHY%'
  GROUP BY h.hadm_id
)
SELECT 
  f.diagnosis_type,
  f.los_group,
  AVG(COALESCE(i.imaging_count, 0)) AS mean_count,
  MIN(COALESCE(i.imaging_count, 0)) AS min_count,
  MAX(COALESCE(i.imaging_count, 0)) AS max_count
FROM filtered_los f
LEFT JOIN imaging_counts i
  ON f.hadm_id = i.hadm_id
GROUP BY f.diagnosis_type, f.los_group;