WITH cohort AS (
  -- Base cohort: males 68-78, ICH (principal dx), post-ICU transfer
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    p.dod,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id AND d.seq_num = 1  -- Principal dx
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd 
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.transfers` t 
    ON a.subject_id = t.subject_id AND a.hadm_id = t.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND (icd.icd_code LIKE 'I61%' OR icd.icd_code = '430')  -- ICH ICD-10/9
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
    AND a.admission_location != 'EMERGENCY DEPARTMENT'
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.transfers` t2 
      WHERE t2.subject_id = a.subject_id AND t2.hadm_id = a.hadm_id 
        AND t2.careunit LIKE '%ICU%' 
        AND t2.eventtype = 'transfer'
    )
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.transfers` t3 
      WHERE t3.subject_id = a.subject_id AND t3.hadm_id = a.hadm_id 
        AND t3.careunit NOT LIKE '%ICU%' 
        AND t3.intime > (SELECT MAX(t4.outtime) FROM `physionet-data.mimiciv_3_1_hosp.transfers` t4 
                         WHERE t4.subject_id = a.subject_id AND t4.hadm_id = a.hadm_id AND t4.careunit LIKE '%ICU%')
    )
),

-- 30-day mortality
mortality AS (
  SELECT 
    c.*,
    CASE 
      WHEN c.hospital_expire_flag = 1 OR (c.dod IS NOT NULL AND TIMESTAMP(c.dod) <= DATE_ADD(DATE(c.admittime), INTERVAL 30 DAY))
      THEN 1 ELSE 0 
    END AS mortality_30d
  FROM cohort c
),

-- AKI
aki AS (
  SELECT 
    m.subject_id,
    m.hadm_id,
    m.admittime,
    -- Baseline: min creat in [-48h, +24h]
    (SELECT MIN(valuenum) FROM `physionet-data.mimiciv_3_1_hosp.labevents` l 
     WHERE l.subject_id = m.subject_id AND l.hadm_id = m.hadm_id 
       AND l.itemid = 50912 AND l.valueuom = 'mg/dL'  -- Creatinine
       AND l.charttime BETWEEN TIMESTAMP_SUB(TIMESTAMP(m.admittime), INTERVAL 48 HOUR) 
                           AND TIMESTAMP_ADD(TIMESTAMP(m.admittime), INTERVAL 24 HOUR)
    ) AS baseline_creat,
    -- Peak: max creat in [admittime, +7d]
    (SELECT MAX(valuenum) FROM `physionet-data.mimiciv_3_1_hosp.labevents` l 
     WHERE l.subject_id = m.subject_id AND l.hadm_id = m.hadm_id 
       AND l.itemid = 50912 AND l.valueuom = 'mg/dL'
       AND l.charttime BETWEEN TIMESTAMP(m.admittime) AND TIMESTAMP_ADD(TIMESTAMP(m.admittime), INTERVAL 7 DAY)
    ) AS peak_creat
  FROM mortality m
),
aki_flags AS (
  SELECT 
    *,
    CASE 
      WHEN baseline_creat > 0 AND SAFE_DIVIDE(peak_creat, baseline_creat) >= 1.5 THEN 1 
      ELSE 0 
    END AS aki_flag
  FROM aki
  WHERE baseline_creat IS NOT NULL AND peak_creat IS NOT NULL
),

-- ARDS (Berlin criteria proxy: intubation + P/F <=300 + PEEP >=5 within 48h ICU)
ards_flags AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON i.subject_id = ce.subject_id AND i.stay_id = ce.stay_id
        INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
        WHERE i.subject_id = c.subject_id AND i.hadm_id = c.hadm_id
          AND i.intime <= TIMESTAMP(c.admittime)  -- ICU during admission
          AND ce.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
          -- Intubation proxy
          AND EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.chartevents` tube 
                      WHERE tube.subject_id = i.subject_id AND tube.stay_id = i.stay_id 
                        AND tube.itemid = 225309 AND tube.value = 'Yes'  -- Endotracheal tube inserted
                        AND tube.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR))
          -- PEEP >=5
          AND EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.chartevents` p 
                      WHERE p.subject_id = i.subject_id AND p.stay_id = i.stay_id 
                        AND p.itemid = 220339 AND p.valuenum >= 5  -- PEEP
                        AND p.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR))
          -- PaO2/FiO2 <=300 (join on same time window, approx concurrent)
          AND EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.chartevents` pa 
                      INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` fi 
                        ON ABS(TIMESTAMP_DIFF(pa.charttime, fi.charttime, HOUR)) <= 1  -- Within 1h
                      WHERE pa.subject_id = i.subject_id AND pa.stay_id = i.stay_id 
                        AND pa.itemid = 220277  -- PaO2
                        AND fi.subject_id = i.subject_id AND fi.stay_id = i.stay_id 
                        AND fi.itemid = 190  -- FiO2
                        AND (CASE WHEN fi.valuenum > 0 THEN pa.valuenum / fi.valuenum ELSE pa.valuenum / 0.21 END) <= 300
                        AND pa.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
                        AND fi.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR))
      ) THEN 1 ELSE 0 
    END AS ards_flag
  FROM cohort c
),

-- Composite risk: Simplified APACHE II score (first 24h ICU)
apache AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    -- Age score
    CASE 
      WHEN p.anchor_age < 45 THEN 0
      WHEN p.anchor_age < 55 THEN 2
      WHEN p.anchor_age < 65 THEN 3
      WHEN p.anchor_age < 75 THEN 5
      ELSE 6
    END AS age_score,
    -- HR score (max >110 =4)
    COALESCE((SELECT MAX(CASE WHEN valuenum > 110 THEN 4 ELSE 0 END) 
              FROM `physionet-data.mimiciv_3_1_icu.chartevents` ch 
              INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ch.subject_id = i.subject_id AND ch.stay_id = i.stay_id
              INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ch.itemid = di.itemid
              WHERE ch.subject_id = c.subject_id AND i.hadm_id = c.hadm_id 
                AND di.abbreviation = 'HR'
                AND ch.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)), 0) AS hr_score,
    -- RR score (max >35 =4; simplified)
    COALESCE((SELECT MAX(CASE WHEN valuenum > 35 THEN 4 ELSE 0 END) 
              FROM `physionet-data.mimiciv_3_1_icu.chartevents` ch 
              INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ch.subject_id = i.subject_id AND ch.stay_id = i.stay_id
              INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ch.itemid = di.itemid
              WHERE ch.subject_id = c.subject_id AND i.hadm_id = c.hadm_id 
                AND di.abbreviation = 'Resp'
                AND ch.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)), 0) AS rr_score,
    -- Temp score (max >40=4 or <30=4; simplified)
    COALESCE((SELECT MAX(CASE WHEN valuenum > 40 OR valuenum < 30 THEN 4 ELSE 0 END) 
              FROM `physionet-data.mimiciv_3_1_icu.chartevents` ch 
              INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ch.subject_id = i.subject_id AND ch.stay_id = i.stay_id
              INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ch.itemid = di.itemid
              WHERE ch.subject_id = c.subject_id AND i.hadm_id = c.hadm_id 
                AND di.abbreviation = 'Temp'
                AND ch.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)), 0) AS temp_score,
    -- Mean BP score (min <0=4; simplified)
    COALESCE((SELECT MAX(CASE WHEN valuenum < 0 THEN 4 ELSE 0 END) 
              FROM `physionet-data.mimiciv_3_1_icu.chartevents` ch 
              INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ch.subject_id = i.subject_id AND ch.stay_id = i.stay_id
              INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ch.itemid = di.itemid
              WHERE ch.subject_id = c.subject_id AND i.hadm_id = c.hadm_id 
                AND di.abbreviation = 'MeanBP'
                AND ch.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)), 0) AS mbp_score,
    -- GCS score (min; simplified total <10=6+)
    COALESCE((SELECT MAX(CASE WHEN valuenum < 10 THEN 6 ELSE 0 END) 
              FROM `physionet-data.mimiciv_3_1_icu.chartevents` ch 
              INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ch.subject_id = i.subject_id AND ch.stay_id = i.stay_id
              INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ch.itemid = di.itemid
              WHERE ch.subject_id = c.subject_id AND i.hadm_id = c.hadm_id 
                AND di.label LIKE '%GCS%'
                AND ch.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)), 0) AS gcs_score,
    -- Creat score (worst in first 24h; stage 3=9)
    COALESCE((SELECT MAX(CASE WHEN valuenum >= 3.5 THEN 9 WHEN valuenum >= 2 THEN 6 WHEN valuenum >= 1.5 THEN 4 ELSE 2 END) 
              FROM `physionet-data.mimiciv_3_1_hosp.labevents` l 
              INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON l.subject_id = i.subject_id AND l.hadm_id = i.hadm_id
              WHERE l.subject_id = c.subject_id AND i.hadm_id = c.hadm_id 
                AND l.itemid = 50912 AND l.valueuom = 'mg/dL'
                AND l.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)), 0) AS creat_score,
    -- Hct score (min <20=6)
    COALESCE((SELECT MAX(CASE WHEN valuenum < 20 THEN 6 ELSE 0 END) 
              FROM `physionet-data.mimiciv_3_1_hosp.labevents` l 
              INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON l.subject_id = i.subject_id AND l.hadm_id = i.hadm_id
              WHERE l.subject_id = c.subject_id AND i.hadm_id = c.hadm_id 
                AND l.itemid = 51222  -- Hct
                AND l.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)), 0) AS hct_score,
    -- WBC score (max >40=4)
    COALESCE((SELECT MAX(CASE WHEN valuenum > 40 THEN 4 ELSE 0 END) 
              FROM `physionet-data.mimiciv_3_1_hosp.labevents` l 
              INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON l.subject_id = i.subject_id AND l.hadm_id = i.hadm_id
              WHERE l.subject_id = c.subject_id AND i.hadm_id = c.hadm_id 
                AND l.itemid = 51301  -- WBC
                AND l.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)), 0) AS wbc_score
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON c.subject_id = p.subject_id
  WHERE EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i WHERE i.subject_id = c.subject_id AND i.hadm_id = c.hadm_id)
),
apache_full AS (
  SELECT 
    subject_id,
    hadm_id,
    (age_score + hr_score + rr_score + temp_score + mbp_score + gcs_score + creat_score + hct_score + wbc_score) AS apache_score  -- Simplified sum (add A-aDO2=0, chronic=0 for ICH)
  FROM apache
),

-- Full cohort with flags
full_cohort AS (
  SELECT 
    m.subject_id,
    m.hadm_id,
    m.admittime,
    m.mortality_30d,
    COALESCE(af.aki_flag, 0) AS aki_flag,
    COALESCE(arf.ards_flag, 0) AS ards_flag,
    COALESCE(ap.apache_score, 0) AS apache_score,
    CASE WHEN m.dod IS NOT NULL THEN DATE_DIFF(DATE(m.dod), DATE(m.admittime), DAY) ELSE NULL END AS survival_days
  FROM mortality m
  LEFT JOIN aki_flags af ON m.subject_id = af.subject_id AND m.hadm_id = af.hadm_id
  LEFT JOIN ards_flags arf ON m.subject_id = arf.subject_id AND m.hadm_id = arf.hadm_id
  LEFT JOIN apache_full ap ON m.subject_id = ap.subject_id AND m.hadm_id = ap.hadm_id
)

-- Final aggregates
SELECT 
  COUNT(DISTINCT subject_id) AS cohort_size,
  ROUND(AVG(mortality_30d) * 100, 2) AS mortality_30d_rate_pct,
  ROUND(AVG(aki_flag) * 100, 2) AS aki_rate_pct,
  ROUND(AVG(ards_flag) * 100, 2) AS ards_rate_pct,
  APPROX_QUANTILES(apache_score, 4)[OFFSET(1)] AS apache_25th,
  APPROX_QUANTILES(apache_score, 4)[OFFSET(2)] AS apache_50th,
  APPROX_QUANTILES(apache_score, 4)[OFFSET(3)] AS apache_75th,
  (SELECT PERCENTILE_CONT(survival_days, 0.5) FROM full_cohort WHERE survival_days IS NOT NULL) AS median_survival_decedents_days
FROM full_cohort;