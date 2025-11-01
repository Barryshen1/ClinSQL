WITH cohort AS (
  -- Base cohort: males 88-98 at admission, ICU stay, pneumonia (first admission only)
  SELECT DISTINCT subject_id
  FROM (
    SELECT 
      p.subject_id,
      a.hadm_id,
      a.admittime,
      ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
      AND a.admittime <= COALESCE(p.dod, '9999-12-31')  -- Alive at admission
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 88 AND 98
      AND (
        -- ICD-9 pneumonia
        (d.icd_version = '9' AND d.icd_code LIKE '48%' AND d.icd_code NOT LIKE '488%')
        OR d.icd_code = '507.0'
        OR (d.icd_version = '10' 
            AND (d.icd_code LIKE 'J09%' OR d.icd_code LIKE 'J1[5-6]%' OR d.icd_code LIKE 'J18%'))
      )
      AND d.seq_num <= CAST(3 AS INT64)  -- Principal or early diagnoses (fix type mismatch)
    GROUP BY p.subject_id, a.hadm_id, a.admittime  -- Ensure pneumonia+ICU admission
    HAVING COUNT(*) >= 1  -- At least one qualifying diagnosis
  ) base
  WHERE rn = 1  -- First admission only
),

outcomes AS (
  SELECT 
    c.subject_id,
    -- Mortality: any fatal admission
    MAX(a.hospital_expire_flag) = 1 AS has_mortality,
    -- Median survival: min days among fatal admissions (for decedents)
    MIN(CASE WHEN a.deathtime IS NOT NULL 
             THEN DATE_DIFF(PARSE_DATE('%Y-%m-%d %H:%M:%S', a.deathtime), 
                            PARSE_DATE('%Y-%m-%d %H:%M:%S', a.admittime), DAY) 
             ELSE NULL END) AS survival_days,
    -- AKI: any stay with AKI (KDIGO: 1.5x baseline Cr within 7d)
    LOGICAL_OR(
      EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` cre
          ON i.subject_id = cre.subject_id 
          AND i.hadm_id = cre.hadm_id 
          AND i.stay_id = cre.stay_id
          AND cre.itemid IN (2001, 227457)  -- Serum Creatinine
          AND cre.valueuom = 'mg/dl'
          AND cre.valuenum > 0
        WHERE i.subject_id = c.subject_id
          AND cre.charttime >= TIMESTAMP_SUB(i.intime, INTERVAL 48 HOUR)
          AND cre.charttime <= TIMESTAMP_ADD(i.intime, INTERVAL 7 DAY)
        GROUP BY i.stay_id
        HAVING 
          -- Baseline: min Cr in [-48h, +6h]
          MIN(CASE WHEN cre.charttime <= TIMESTAMP_ADD(i.intime, INTERVAL 6 HOUR)
                   THEN cre.valuenum END) > 0
          -- Check if any Cr >= 1.5 * baseline within window
          AND MAX(cre.valuenum) >= 1.5 * MIN(CASE WHEN cre.charttime <= TIMESTAMP_ADD(i.intime, INTERVAL 6 HOUR)
                                                  THEN cre.valuenum END)
      )
    ) AS has_aki,
    -- ARDS: any diagnosis in any admission
    LOGICAL_OR(
      EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
          ON d.subject_id = a2.subject_id AND d.hadm_id = a2.hadm_id
        WHERE d.subject_id = c.subject_id
          AND a2.admittime <= COALESCE(p.dod, '9999-12-31')
          AND d.icd_code IN ('518.5', '518.82', '696.1', 'J80', 'J96.00', 'J96.01', 'J96.02')
      )
    ) AS has_ards,
    -- Composite risk proxy: sum of key chartevents scores (e.g., APACHE-like) in first ICU stay
    COALESCE(
      (SELECT SUM(cre.valuenum)
       FROM `physionet-data.mimiciv_3_1_icu.icustays` i
       INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` cre
         ON i.subject_id = cre.subject_id AND i.stay_id = cre.stay_id
       CROSS JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
       WHERE i.subject_id = c.subject_id
         AND cre.charttime BETWEEN i.intime AND i.outtime
         AND cre.itemid IN (21011, 21012, 21013, 21014, 21015, 21016, 21017, 21018, 21019, 21020, 21021, 21022, 21023, 21024, 21025)  -- APACHE items approx
         AND cre.valuenum IS NOT NULL
       ORDER BY i.intime
       LIMIT 1), 0
    ) AS risk_score
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.subject_id = a.subject_id
  CROSS JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  GROUP BY c.subject_id
)

-- Final aggregates
SELECT 
  COUNT(DISTINCT o.subject_id) AS cohort_size,
  
  -- Composite risk score distribution
  MIN(o.risk_score) AS risk_min,
  PERCENTILE_CONT(o.risk_score, 0.25) OVER () AS risk_q25,
  PERCENTILE_CONT(o.risk_score, 0.5) OVER () AS risk_median,
  PERCENTILE_CONT(o.risk_score, 0.75) OVER () AS risk_q75,
  MAX(o.risk_score) AS risk_max,
  
  -- In-hospital mortality rate (%)
  ROUND(AVG(CAST(o.has_mortality AS FLOAT)) * 100, 2) AS mortality_rate_pct,
  
  -- AKI rate (%)
  ROUND(AVG(CAST(o.has_aki AS FLOAT)) * 100, 2) AS aki_rate_pct,
  
  -- ARDS rate (%)
  ROUND(AVG(CAST(o.has_ards AS FLOAT)) * 100, 2) AS ards_rate_pct,
  
  -- Median survival days for decedents
  (SELECT PERCENTILE_CONT(survival_days, 0.5) 
   FROM outcomes 
   WHERE survival_days IS NOT NULL) AS median_survival_days_decedents

FROM outcomes o;