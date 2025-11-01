WITH
-- CTE to identify the first ICU stay for each hospital admission for the target population
first_icu_stays AS (
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        intime,
        admittime,
        dischtime,
        hospital_expire_flag
    FROM (
        SELECT
            p.subject_id,
            a.hadm_id,
            icu.stay_id,
            icu.intime,
            a.admittime,
            a.dischtime,
            a.hospital_expire_flag,
            ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY icu.intime) AS rn
        FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
            ON p.subject_id = a.subject_id
        INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
            ON a.hadm_id = icu.hadm_id
        WHERE
            p.gender = 'M'
            AND p.anchor_age BETWEEN 68 AND 78
    ) AS ranked_stays
    WHERE rn = 1
),

-- CTE for the final cohort: patients from the base population who received vasopressors in the first 72h of ICU stay
vaso_cohort AS (
    SELECT DISTINCT
        fis.subject_id,
        fis.hadm_id,
        fis.stay_id,
        fis.intime,
        fis.admittime,
        fis.dischtime,
        fis.hospital_expire_flag
    FROM first_icu_stays AS fis
    INNER JOIN `physionet-data.mimiciv_3_1_icu.ingredientevents` AS ie
        ON fis.stay_id = ie.stay_id
    WHERE
        -- Vasopressor itemids from ingredientevents
        ie.itemid IN (
            221906, -- Norepinephrine
            221289, -- Epinephrine
            221749, -- Phenylephrine
            222315, -- Vasopressin
            221662  -- Dopamine
        )
        -- Medication started within 72 hours of ICU admission
        AND ie.starttime <= DATETIME_ADD(fis.intime, INTERVAL 72 HOUR)
),

-- Efficiently count lab tests in the first 72h for the cohort
labs_72h AS (
    SELECT
        vc.stay_id,
        COUNT(le.labevent_id) AS lab_count
    FROM vaso_cohort AS vc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON vc.hadm_id = le.hadm_id
    WHERE le.charttime BETWEEN vc.intime AND DATETIME_ADD(vc.intime, INTERVAL 72 HOUR)
    GROUP BY vc.stay_id
),

-- Efficiently count imaging from chartevents in the first 72h
imaging_ce_72h AS (
    SELECT
        vc.stay_id,
        COUNT(ce.itemid) AS imaging_ce_count
    FROM vaso_cohort AS vc
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON vc.stay_id = ce.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
        ON ce.itemid = di.itemid
    WHERE
        di.category = 'Imaging'
        AND ce.charttime BETWEEN vc.intime AND DATETIME_ADD(vc.intime, INTERVAL 72 HOUR)
    GROUP BY vc.stay_id
),

-- Efficiently count imaging from HCPCS codes in the first 72h (approximate)
imaging_hcpcs_72h AS (
    SELECT
        vc.stay_id,
        COUNT(hc.hcpcs_cd) AS imaging_hcpcs_count
    FROM vaso_cohort AS vc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS hc
        ON vc.hadm_id = hc.hadm_id
    WHERE
        hc.hcpcs_cd BETWEEN '70000' AND '79999' -- Standard CPT range for radiology
        AND hc.chartdate BETWEEN DATE(vc.intime) AND DATE(DATETIME_ADD(vc.intime, INTERVAL 72 HOUR))
    GROUP BY vc.stay_id
),

-- CTE to count procedures for the entire hospital stay for the cohort
procedure_counts AS (
    SELECT
        hadm_id,
        COUNT(icd_code) AS procedure_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE hadm_id IN (SELECT hadm_id FROM vaso_cohort)
    GROUP BY hadm_id
),

-- CTE to determine 30-day readmissions, filtered for cohort patients for efficiency
readmission_data AS (
    SELECT
        hadm_id,
        CASE
            WHEN DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30 THEN 1
            ELSE 0
        END AS readmitted_30d
    FROM (
        SELECT
            a.hadm_id,
            a.dischtime,
            LEAD(a.admittime, 1) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS next_admittime
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
        WHERE a.subject_id IN (SELECT DISTINCT subject_id FROM vaso_cohort)
    ) AS adm_ranked
),

-- CTE to combine all data and create quartiles based on diagnostic load
final_data AS (
    SELECT
        vc.hadm_id,
        DATETIME_DIFF(vc.dischtime, vc.admittime, HOUR) / 24.0 AS los_hospital,
        vc.hospital_expire_flag,
        COALESCE(pc.procedure_count, 0) AS procedure_count,
        COALESCE(rd.readmitted_30d, 0) AS readmitted_30d,
        NTILE(4) OVER (ORDER BY (
            COALESCE(l.lab_count, 0)
            + COALESCE(ic.imaging_ce_count, 0)
            + COALESCE(ih.imaging_hcpcs_count, 0)
        )) AS diagnostic_quartile
    FROM vaso_cohort AS vc
    LEFT JOIN labs_72h AS l ON vc.stay_id = l.stay_id
    LEFT JOIN imaging_ce_72h AS ic ON vc.stay_id = ic.stay_id
    LEFT JOIN imaging_hcpcs_72h AS ih ON vc.stay_id = ih.stay_id
    LEFT JOIN procedure_counts AS pc ON vc.hadm_id = pc.hadm_id
    LEFT JOIN readmission_data AS rd ON vc.hadm_id = rd.hadm_id
)

-- Final aggregation and reporting by diagnostic load quartile
SELECT
    diagnostic_quartile,
    COUNT(hadm_id) AS number_of_patients,
    AVG(procedure_count) AS avg_procedure_count,
    AVG(los_hospital) AS avg_hospital_los_days,
    AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
    AVG(readmitted_30d) AS readmission_rate_30d
FROM final_data
GROUP BY diagnostic_quartile
ORDER BY diagnostic_quartile;