WITH lower_gi_bleed_admissions AS (
  SELECT DISTINCT di.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code IN ('5693', 'K922') -- Lower GI bleeding ICD-9 and ICD-10
),
first_icu_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN (
    SELECT subject_id, MIN(intime) AS first_intime
    FROM physionet-data.mimiciv_3_1_icu.icustays
    GROUP BY subject_id
  ) first ON icu.subject_id = first.subject_id AND icu.intime = first.first_intime
  JOIN physionet-data.mimiciv_3_1_hosp.admissions adm ON icu.hadm_id = adm.hadm_id
  WHERE icu.hadm_id IN (SELECT hadm_id FROM lower_gi_bleed_admissions)
),
female_patients AS (
  SELECT subject_id, anchor_age
  FROM physionet-data.mimiciv_3_1_hosp.patients
  WHERE gender = 'F' AND anchor_age BETWEEN 87 AND 97
),
procedures_in_48h AS (
  SELECT
    ficu.stay_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_procedures
  FROM first_icu_stays ficu
  JOIN physionet-data.mimiciv_3_1_hosp.procedures_icd proc
    ON ficu.hadm_id = proc.hadm_id
  WHERE proc.chartdate <= ficu.intime + INTERVAL 48 HOUR
  GROUP BY ficu.stay_id
),
quintile_data AS (
  SELECT
    p.stay_id,
    p.distinct_procedures,
    ficu.los,
    ficu.hospital_expire_flag,
    NTILE(5) OVER (ORDER BY p.distinct_procedures) AS procedure_quintile
  FROM procedures_in_48h p
  JOIN first_icu_stays ficu ON p.stay_id = ficu.stay_id
)
SELECT
  procedure_quintile,
  AVG(distinct_procedures) AS mean_procedure_count,
  AVG(los) AS mean_icu_los_days,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent
FROM quintile_data
GROUP BY procedure_quintile
ORDER BY procedure_quintile;