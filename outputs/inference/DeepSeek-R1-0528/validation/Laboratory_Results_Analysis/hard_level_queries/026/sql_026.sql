WITH 
hepatic_cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    DATETIME_ADD(adm.admittime, INTERVAL 48 HOUR) AS adm_48hr
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year BETWEEN 75 AND 85
    AND adm.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code IN ('570','571','572.2','572.3','572.4','572.8','573.3','573.4'))
        OR 
        (icd_version = 10 AND icd_code IN ('K72.0','K72.1','K72.9','K76.2','K76.5','K76.6','K76.7'))
    )
),
control_cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    DATETIME_ADD(adm.admittime, INTERVAL 48 HOUR) AS adm_48hr
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year BETWEEN 75 AND 85
    AND adm.hadm_id NOT IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code IN ('570','571','572.2','572.3','572.4','572.8','573.3','573.4'))
        OR 
        (icd_version = 10 AND icd_code IN ('K72.0','K72.1','K72.9','K76.2','K76.5','K76.6','K76.7'))
    )
),
hepatic_instability AS (
  SELECT 
    hc.hadm_id,
    COUNT(DISTINCT dlab.category) AS instability_score
  FROM hepatic_cohort hc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON hc.hadm_id = le.hadm_id
    AND le.charttime BETWEEN hc.admittime AND hc.adm_48hr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON le.itemid = dlab.itemid
  WHERE 
    le.flag IS NOT NULL 
    AND (le.flag LIKE '%panic%')
  GROUP BY hc.hadm_id
),
hepatic_labs AS (
  SELECT 
    hc.hadm_id,
    COUNT(*) AS critical_lab_count
  FROM hepatic_cohort hc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON hc.hadm_id = le.hadm_id
    AND le.charttime BETWEEN hc.admittime AND hc.adm_48hr
  WHERE 
    le.flag IS NOT NULL 
    AND (le.flag LIKE '%panic%')
  GROUP BY hc.hadm_id
),
control_labs AS (
  SELECT 
    cc.hadm_id,
    COUNT(*) AS critical_lab_count
  FROM control_cohort cc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON cc.hadm_id = le.hadm_id
    AND le.charttime BETWEEN cc.admittime AND cc.adm_48hr
  WHERE 
    le.flag IS NOT NULL 
    AND (le.flag LIKE '%panic%')
  GROUP BY cc.hadm_id
),
hepatic_summary AS (
  SELECT 
    'Hepatic failure cohort' AS cohort_type,
    MAX(COALESCE(hi.instability_score, 0)) AS max_instability_score,
    AVG(hc.hospital_expire_flag) * 100 AS mortality_percentage,
    AVG(hc.los_days) AS avg_los_days,
    AVG(COALESCE(hl.critical_lab_count, 0)) AS avg_critical_labs_per_patient
  FROM hepatic_cohort hc
  LEFT JOIN hepatic_instability hi ON hc.hadm_id = hi.hadm_id
  LEFT JOIN hepatic_labs hl ON hc.hadm_id = hl.hadm_id
  GROUP BY cohort_type
),
control_summary AS (
  SELECT 
    'Control cohort' AS cohort_type,
    NULL AS max_instability_score,
    AVG(cc.hospital_expire_flag) * 100 AS mortality_percentage,
    AVG(cc.los_days) AS avg_los_days,
    AVG(COALESCE(cl.critical_lab_count, 0)) AS avg_critical_labs_per_patient
  FROM control_cohort cc
  LEFT JOIN control_labs cl ON cc.hadm_id = cl.hadm_id
  GROUP BY cohort_type
)
SELECT * FROM hepatic_summary
UNION ALL
SELECT * FROM control_summary;