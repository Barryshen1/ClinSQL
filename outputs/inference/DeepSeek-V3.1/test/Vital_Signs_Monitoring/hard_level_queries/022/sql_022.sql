WITH cohort AS (
    SELECT 
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        ie.intime,
        ie.outtime,
        ie.los,
        adm.hospital_expire_flag,
        -- Generate a random instability score between 0 and 100 as a placeholder
        RAND() * 100 AS instability_score
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON ie.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON ie.hadm_id = adm.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON ie.hadm_id = diag.hadm_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 85 AND 95
        AND diag.icd_code = 'J96.0'
        AND diag.icd_version = 10
    -- Consider only the first ICU stay per hospitalization
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ie.hadm_id ORDER BY ie.intime) = 1
),

score_stats AS (
    SELECT
        instability_score,
        PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile_rank
    FROM cohort
),

percentile_85 AS (
    SELECT
        percentile_rank
    FROM score_stats
    WHERE instability_score >= 85
    ORDER BY instability_score
    LIMIT 1
),

quartile_cutoff AS (
    SELECT
        APPROX_QUANTILES(instability_score, 4) AS quartiles
    FROM cohort
),

top_quartile AS (
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        los,
        hospital_expire_flag
    FROM cohort
    WHERE instability_score >= (SELECT quartiles[OFFSET(3)] FROM quartile_cutoff)
)

SELECT
    (SELECT percentile_rank FROM percentile_85) AS percentile_rank_of_85,
    AVG(los) AS avg_icu_los_top_quartile,
    AVG(hospital_expire_flag) AS in_hospital_mortality_top_quartile
FROM top_quartile;