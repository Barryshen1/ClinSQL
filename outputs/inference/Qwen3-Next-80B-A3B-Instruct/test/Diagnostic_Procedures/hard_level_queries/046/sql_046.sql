WITH first_icu_stays AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM physionet-data.mimiciv_3_1_icu.icustays i
),
ards_female_cohort AS (
  SELECT DISTINCT
    fis.stay_id,
    fis.subject_id,
    fis.hadm_id,
    fis.intime
  FROM first_icu_stays fis
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON fis.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di ON fis.hadm_id = di.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND fis.rn = 1
    AND (
      LOWER(did.long_title) LIKE '%acute respiratory distress syndrome%'
      OR di.icd_code = 'J80'
    )
),
procedure_counts_72h AS (
  SELECT
    i.stay_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procedures
  FROM first_icu_stays i
  LEFT JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe 
    ON i.stay_id = pe.stay_id 
    AND pe.starttime >= i.intime 
    AND pe.starttime <= TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY i.stay_id
),
all_icu_metrics AS (
  SELECT
    APPROX_QUANTILES(pc.distinct_procedures, 100)[OFFSET(75)] AS p75_procedures_all,
    APPROX_QUANTILES(pc.distinct_procedures, 100)[OFFSET(90)] AS p90_procedures_all,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS mean_los_all,
    AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS mortality_rate_all
  FROM first_icu_stays fis
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON fis.hadm_id = a.hadm_id
  LEFT JOIN procedure_counts_72h pc ON fis.stay_id = pc.stay_id
),
ards_female_min AS (
  SELECT
    MIN(pc.distinct_procedures) AS min_procedures_ards_female
  FROM ards_female_cohort af
  LEFT JOIN procedure_counts_72h pc ON af.stay_id = pc.stay_id
)
SELECT
  af.min_procedures_ards_female,
  ai.p75_procedures_all,
  ai.p90_procedures_all,
  ai.mean_los_all,
  ai.mortality_rate_all
FROM ards_female_min af
CROSS JOIN all_icu_metrics ai;