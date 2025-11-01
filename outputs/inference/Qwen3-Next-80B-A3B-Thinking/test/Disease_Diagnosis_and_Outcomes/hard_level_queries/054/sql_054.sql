WITH female_59_69 AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    p.gender, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag, 
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 59 AND 69
),

charlson_scores AS (
  SELECT 
    d.subject_id,
    SUM(
      CASE WHEN d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%') THEN 1 ELSE 0 END +
      CASE WHEN d.icd_version = 10 AND d.icd_code LIKE 'I50%' THEN 1 ELSE 0 END +
      CASE WHEN d.icd_version = 10 AND d.icd_code LIKE 'I70%' THEN 1 ELSE 0 END +
      CASE WHEN d.icd_version = 10 AND d.icd_code BETWEEN 'I60' AND 'I69' THEN 1 ELSE 0 END +
      CASE WHEN d.icd_version = 10 AND d.icd_code BETWEEN 'F01' AND 'F03' THEN 1 ELSE 0 END +
      CASE WHEN d.icd_version = 10 AND d.icd_code BETWEEN 'J40' AND 'J47' THEN 1 ELSE 0 END +
      CASE WHEN d.icd_version = 10 AND d.icd_code BETWEEN 'M05' AND 'M06' THEN 1 ELSE 0 END +
      CASE WHEN d.icd_version = 10 AND d.icd_code BETWEEN 'K25' AND 'K28' THEN 1 ELSE 0 END +
      CASE WHEN d.icd_version = 10 AND d.icd_code BETWEEN 'K70' AND 'K77' THEN 1 ELSE 0 END +
      CASE WHEN d.icd_version = 10 AND (d.icd_code LIKE 'E10.0%' OR d.icd_code LIKE 'E11.0%') THEN 1 ELSE 0 END +
      CASE WHEN d.icd_version = 10 AND (d.icd_code LIKE 'E10.1%' OR d.icd_code LIKE 'E11.1%' OR d.icd_code LIKE 'E10.2%' OR d.icd_code LIKE 'E11.2%' OR d.icd_code LIKE 'E10.3%' OR d.icd_code LIKE 'E11.3%' OR d.icd_code LIKE 'E10.4%' OR d.icd_code LIKE 'E11.4%' OR d.icd_code LIKE 'E10.5%' OR d.icd_code LIKE 'E11.5%' OR d.icd_code LIKE 'E10.6%' OR d.icd_code LIKE 'E11.6%' OR d.icd_code LIKE 'E10.7%' OR d.icd_code LIKE 'E11.7%' OR d.icd_code LIKE 'E10.8%' OR d.icd_code LIKE 'E11.8%') THEN 2 ELSE 0 END +
      CASE WHEN d.icd_version = 10 AND (d.icd_code LIKE 'G81%' OR d.icd_code LIKE 'G82%') THEN 2 ELSE 0 END +
      CASE WHEN d.icd_version = 10 AND (d.icd_code LIKE 'N18%' OR d.icd_code LIKE 'N19%') THEN 2 ELSE 0 END +
      CASE WHEN d.icd_version = 10 AND d.icd_code BETWEEN 'C00' AND 'C97' THEN 2 ELSE 0 END +
      CASE WHEN d.icd_version = 10 AND d.icd_code BETWEEN 'C91' AND 'C95' THEN 2 ELSE 0 END +
      CASE WHEN d.icd_version = 10 AND d.icd_code BETWEEN 'C81' AND 'C90' THEN 2 ELSE 0 END +
      CASE WHEN d.icd_version = 10 AND d.icd_code BETWEEN 'C77' AND 'C79' THEN 6 ELSE 0 END +
      CASE WHEN d.icd_version = 10 AND d.icd_code = 'B20' THEN 6 ELSE 0 END
    ) AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.subject_id
),

pe_diagnoses AS (
  SELECT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10 AND icd_code LIKE 'I26%'
),

admissions_with_charlson_pe AS (
  SELECT 
    f.*,
    c.charlson_score,
    CASE WHEN p.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_pe,
    CASE WHEN c.charlson_score >= 3 AND p.subject_id IS NOT NULL THEN 1 ELSE 0 END AS is_case,
    CASE WHEN f.dod IS NOT NULL AND f.dod <= f.dischtime + INTERVAL '30' DAY THEN 1 ELSE 0 END AS thirty_day_mortality
  FROM female_59_69 f
  LEFT JOIN charlson_scores c ON f.subject_id = c.subject_id
  LEFT JOIN pe_diagnoses p ON f.subject_id = p.subject_id AND f.hadm_id = p.hadm_id
),

cardio_complications AS (
  SELECT 
    a.hadm_id,
    MAX(CASE WHEN d.icd_version = 10 AND (
      d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR 
      d.icd_code LIKE 'I50%' OR d.icd_code LIKE 'I42%' OR 
      d.icd_code LIKE 'I44%' OR d.icd_code LIKE 'I47%' OR 
      d.icd_code LIKE 'I48%' OR d.icd_code LIKE 'I49%' OR 
      d.icd_code LIKE 'I51%' OR d.icd_code LIKE 'I63%' OR 
      d.icd_code LIKE 'I64%'
    ) THEN 1 ELSE 0 END) AS has_cardio_comp
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  GROUP BY a.hadm_id
),

neuro_complications AS (
  SELECT 
    a.hadm_id,
    MAX(CASE WHEN d.icd_version = 10 AND (
      d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR 
      d.icd_code LIKE 'I62%' OR d.icd_code LIKE 'I63%' OR 
      d.icd_code LIKE 'I64%' OR d.icd_code LIKE 'G40%' OR 
      d.icd_code LIKE 'G41%' OR d.icd_code LIKE 'G93%' OR 
      d.icd_code LIKE 'R56%'
    ) THEN 1 ELSE 0 END) AS has_neuro_comp
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  GROUP BY a.hadm_id
),

survivor_los AS (
  SELECT 
    hadm_id,
    CASE WHEN hospital_expire_flag = 0 THEN 
      DATE_DIFF(dischtime, admittime, DAY) 
    ELSE NULL 
    END AS los_survivor
  FROM admissions_with_charlson_pe
)

SELECT 
  'Case Group' AS group_type,
  AVG(charlson_score) AS mean_charlson,
  AVG(thirty_day_mortality) AS thirty_day_mortality_rate,
  AVG(cc.has_cardio_comp) AS cardio_comp_rate,
  AVG(nc.has_neuro_comp) AS neuro_comp_rate,
  AVG(sl.los_survivor) AS avg_survivor_los
FROM admissions_with_charlson_pe acp
LEFT JOIN cardio_complications cc ON acp.hadm_id = cc.hadm_id
LEFT JOIN neuro_complications nc ON acp.hadm_id = nc.hadm_id
LEFT JOIN survivor_los sl ON acp.hadm_id = sl.hadm_id
WHERE acp.is_case = 1

UNION ALL

SELECT 
  'Control Group' AS group_type,
  AVG(charlson_score) AS mean_charlson,
  AVG(thirty_day_mortality) AS thirty_day_mortality_rate,
  AVG(cc.has_cardio_comp) AS cardio_comp_rate,
  AVG(nc.has_neuro_comp) AS neuro_comp_rate,
  AVG(sl.los_survivor) AS avg_survivor_los
FROM admissions_with_charlson_pe acp
LEFT JOIN cardio_complications cc ON acp.hadm_id = cc.hadm_id
LEFT JOIN neuro_complications nc ON acp.hadm_id = nc.hadm_id
LEFT JOIN survivor_los sl ON acp.hadm_id = sl.hadm_id
WHERE acp.is_case = 0;