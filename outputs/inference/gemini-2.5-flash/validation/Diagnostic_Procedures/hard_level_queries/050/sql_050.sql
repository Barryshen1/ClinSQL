WITH EligibleICUStays AS (
    -- Select unique ICU stays for male patients aged 76-86 with an AMI diagnosis
    SELECT
        p.subject_id,
        ad.hadm_id,
        ic.stay_id,
        ic.intime,
        ic.los AS icu_los_days, -- ICU LOS in days, as specified in schema
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON p.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` ic
        ON ad.hadm_id = ic.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.hadm_id = di.hadm_id AND p.subject_id = di.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 76 AND 86 -- Age at anchor year
        AND (
            -- ICD-9 codes for Acute Myocardial Infarction
            (di.icd_version = 9 AND di.icd_code LIKE '410%')
            OR
            -- ICD-10 codes for Acute Myocardial Infarction (I21 and I22 are main categories)
            (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
        )
    GROUP BY -- Ensure one row per qualifying ICU stay
        p.subject_id,
        ad.hadm_id,
        ic.stay_id,
        ic.intime,
        ic.los,
        ad.hospital_expire_flag
),
ProceduresFirst24h AS (
    -- Count distinct procedures in the first 24 hours of ICU stay for each eligible stay
    SELECT
        eis.stay_id,
        COUNT(DISTINCT pr.icd_code) AS distinct_procedure_count_24h
    FROM
        EligibleICUStays eis
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
        ON eis.hadm_id = pr.hadm_id
        -- Filter procedures to those occurring within the first 24 hours of ICU intime.
        -- 'chartdate' is DATE type for procedures, so considering procedures on:
        -- 1. The same calendar day as intime.
        -- 2. The next calendar day, if the 24-hour window extends into it.
        AND DATE(pr.chartdate) >= DATE(eis.intime)
        AND DATE(pr.chartdate) <= DATE(DATETIME_ADD(eis.intime, INTERVAL 24 HOUR))
    GROUP BY
        eis.stay_id
),
PatientDataWithProcCounts AS (
    -- Combine eligible ICU stay data with the calculated distinct procedure counts
    SELECT
        eis.subject_id,
        eis.hadm_id,
        eis.stay_id,
        eis.intime,
        eis.icu_los_days,
        eis.hospital_expire_flag,
        -- Use COALESCE to assign 0 procedures if no procedures were found in the 24h window
        COALESCE(p24.distinct_procedure_count_24h, 0) AS distinct_procedure_count_24h_final
    FROM
        EligibleICUStays eis
    LEFT JOIN
        ProceduresFirst24h p24
        ON eis.stay_id = p24.stay_id
),
PatientQuartiles AS (
    -- Assign each patient stay to a quartile based on their distinct procedure count
    SELECT
        *,
        NTILE(4) OVER (ORDER BY distinct_procedure_count_24h_final) AS procedure_quartile
    FROM
        PatientDataWithProcCounts
)
-- Final aggregation to report metrics for each quartile
SELECT
    procedure_quartile,
    CAST(AVG(distinct_procedure_count_24h_final) AS BIGNUMERIC) AS mean_procedure_count,
    CAST(AVG(icu_los_days) AS BIGNUMERIC) AS mean_icu_los_days,
    CAST((100.0 * SUM(hospital_expire_flag) / COUNT(*)) AS BIGNUMERIC) AS hospital_mortality_percent
FROM
    PatientQuartiles
GROUP BY
    procedure_quartile
ORDER BY
    procedure_quartile;