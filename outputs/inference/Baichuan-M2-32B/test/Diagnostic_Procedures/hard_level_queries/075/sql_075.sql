WITH eligible_patients AS (
    SELECT
        subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
      AND anchor_age BETWEEN 39 AND 49
),
dkadmissions AS (
    SELECT
        d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
    WHERE dd.icd_code = 'E10.10'  -- ICD-10 code for Diabetic Ketoacidosis
      AND dd.icd_version = 10
),
first_icu_stays AS (
    SELECT
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.los,
        ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN dkadmissions d ON i.hadm_id = d.hadm_id
    JOIN eligible_patients e ON i.subject_id = e.subject_id
    WHERE i.hadm_id IS NOT NULL
),
procedures_24h AS (
    SELECT
        f.subject_id,
        f.hadm_id,
        f.stay_id,
        COUNT(DISTINCT p.icd_code) AS procedure_count
    FROM first_icu_stays f
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
        ON f.subject_id = p.subject_id
        AND f.hadm_id = p.hadm_id
        AND p.chartdate BETWEEN DATE(f.intime) AND DATE(f.intime) + 1
    WHERE f.rn = 1  -- only first ICU stay per admission
    GROUP BY f.subject_id, f.hadm_id, f.stay_id
),
with_procedure_count AS (
    SELECT
        f.subject_id,
        f.hadm_id,
        f.stay_id,
        f.intime,
        f.los,
        COALESCE(p.procedure_count, 0) AS procedure_count
    FROM first_icu_stays f
    LEFT JOIN procedures_24h p
        ON f.subject_id = p.subject_id
        AND f.hadm_id = p.hadm_id
        AND f.stay_id = p.stay_id
    WHERE f.rn = 1
),
with_procedure_count_with_mortality AS (
    SELECT
        w.subject_id,
        w.hadm_id,
        w.stay_id,
        w.intime,
        w.los,
        w.procedure_count,
        a.hospital_expire_flag
    FROM with_procedure_count w
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON w.hadm_id = a.hadm_id
),
with_quintiles AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY procedure_count) AS quintile
    FROM with_procedure_count_with_mortality
),
grouped AS (
    SELECT
        quintile,
        COUNT(DISTINCT hadm_id) AS num_stays,
        AVG(procedure_count) AS mean_procedure_count,
        MIN(procedure_count) AS min_procedure_count,
        MAX(procedure_count) AS max_procedure_count,
        AVG(los / 24.0) AS mean_los_days,
        AVG(hospital_expire_flag) * 100 AS mortality_pct
    FROM with_quintiles
    GROUP BY quintile
)
SELECT
    quintile,
    num_stays,
    mean_procedure_count,
    min_procedure_count,
    max_procedure_count,
    mean_los_days,
    mortality_pct
FROM grouped
ORDER BY quintile;