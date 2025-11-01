WITH base_cohort AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pats
        ON ad.subject_id = pats.subject_id
    WHERE
        pats.gender = 'F'
        AND pats.anchor_age BETWEEN 51 AND 61
        -- Filter for surgical admissions using DRG codes
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.drgcodes` AS drg
            WHERE drg.hadm_id = ad.hadm_id
            AND drg.drg_type = 'SURGICAL'
        )
),
-- Step 2: Get all distinct drugs prescribed within the first 24 hours for each admission in the base cohort
-- And mark if they are high-risk.
adms_24h_distinct_prescriptions AS (
    SELECT
        bc.subject_id,
        bc.hadm_id,
        LOWER(presc.drug) AS drug_name,
        -- Flag high-risk drugs. This list is an assumption based on common clinical practice.
        (CASE
            WHEN LOWER(presc.drug) LIKE '%insulin%' AND LOWER(presc.drug) NOT LIKE '%insulin pen%'  THEN TRUE
            WHEN LOWER(presc.drug) LIKE '%heparin%' THEN TRUE
            WHEN LOWER(presc.drug) LIKE '%warfarin%' THEN TRUE
            WHEN LOWER(presc.drug) LIKE '%fentanyl%' THEN TRUE
            WHEN LOWER(presc.drug) LIKE '%morphine%' THEN TRUE
            WHEN LOWER(presc.drug) LIKE '%hydromorphone%' THEN TRUE
            WHEN LOWER(presc.drug) LIKE '%lorazepam%' THEN TRUE
            WHEN LOWER(presc.drug) LIKE '%midazolam%' THEN TRUE
            WHEN LOWER(presc.drug) LIKE '%propofol%' THEN TRUE
            WHEN LOWER(presc.drug) LIKE '%norepinephrine%' THEN TRUE
            WHEN LOWER(presc.drug) LIKE '%epinephrine%' THEN TRUE
            WHEN LOWER(presc.drug) LIKE '%vasopressin%' THEN TRUE
            WHEN LOWER(presc.drug) LIKE '%dobutamine%' THEN TRUE
            WHEN LOWER(presc.drug) LIKE '%dopamine%' THEN TRUE
            WHEN LOWER(presc.drug) LIKE '%amiodarone%' THEN TRUE
            WHEN LOWER(presc.drug) LIKE '%ketamine%' THEN TRUE
            WHEN LOWER(presc.drug) LIKE '%dexmedetomidine%' THEN TRUE
            WHEN LOWER(presc.drug) LIKE '%cisatracurium%' THEN TRUE
            WHEN LOWER(presc.drug) LIKE '%rocuronium%' THEN TRUE
            WHEN LOWER(presc.drug) LIKE '%vecuronium%' THEN TRUE
            ELSE FALSE
        END) AS is_high_risk_drug
    FROM
        base_cohort AS bc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS presc
        ON bc.subject_id = presc.subject_id
        AND bc.hadm_id = presc.hadm_id
    WHERE
        presc.starttime BETWEEN bc.admittime AND DATETIME_ADD(bc.admittime, INTERVAL 24 HOUR)
    GROUP BY -- Ensure only distinct drug names relevant to the 24h window are considered per hadm_id
        bc.subject_id, bc.hadm_id, LOWER(presc.drug), is_high_risk_drug -- Added is_high_risk_drug to GROUP BY
),
-- Calculate medication complexity score for each admission
medication_complexity_scores AS (
    SELECT
        bc.subject_id,
        bc.hadm_id,
        bc.admittime,
        bc.dischtime,
        bc.hospital_expire_flag,
        COALESCE(SUM(CASE
                WHEN pds.is_high_risk_drug THEN 2 -- Apply weight of 2 for high-risk drugs
                ELSE 1 -- Apply weight of 1 for non-high-risk unique drugs
            END), 0) AS medication_complexity_score -- Assign 0 if no drugs in 24h (due to LEFT JOIN)
    FROM
        base_cohort AS bc
    LEFT JOIN
        adms_24h_distinct_prescriptions AS pds
        ON bc.subject_id = pds.subject_id
        AND bc.hadm_id = pds.hadm_id
    GROUP BY
        bc.subject_id, bc.hadm_id, bc.admittime, bc.dischtime, bc.hospital_expire_flag
),
-- Step 3: Get all admissions for subjects in our base cohort to correctly calculate readmission
all_admissions_for_cohort_subjects AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        -- Find the next admission for the same patient, ordered by admission time
        LEAD(ad.admittime) OVER (PARTITION BY ad.subject_id ORDER BY ad.admittime, ad.hadm_id) AS next_admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    WHERE ad.subject_id IN (SELECT DISTINCT subject_id FROM base_cohort) -- Restrict to subjects present in our base cohort
),
-- Calculate 30-day readmission flag for the relevant admissions (those in base_cohort)
admissions_with_readmission_status AS (
    SELECT
        mcs.subject_id,
        mcs.hadm_id,
        mcs.admittime,
        mcs.dischtime,
        mcs.hospital_expire_flag,
        mcs.medication_complexity_score,
        CASE
            WHEN aas.next_admittime IS NOT NULL
            AND DATE_DIFF(aas.next_admittime, mcs.dischtime, DAY) <= 30 -- Within 30 days
            AND aas.next_admittime > mcs.dischtime -- Must be strictly after current discharge
            THEN 1
            ELSE 0
        END AS readmission_30_day
    FROM
        medication_complexity_scores AS mcs
    LEFT JOIN
        all_admissions_for_cohort_subjects AS aas
        ON mcs.hadm_id = aas.hadm_id AND mcs.subject_id = aas.subject_id
),
-- Step 4: Assign medication complexity quartiles
cohort_with_quartiles AS (
    SELECT
        ars.subject_id,
        ars.hadm_id,
        ars.admittime,
        ars.dischtime,
        ars.hospital_expire_flag,
        ars.medication_complexity_score,
        ars.readmission_30_day,
        NTILE(4) OVER (ORDER BY ars.medication_complexity_score ASC) AS medication_complexity_quartile
    FROM
        admissions_with_readmission_status AS ars
)
-- Step 5: Final Aggregation by Quartile
SELECT
    medication_complexity_quartile,
    COUNT(hadm_id) AS admissions_count,
    ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0), 2) AS average_los_days,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_percent,
    ROUND(AVG(readmission_30_day) * 100, 2) AS readmission_30_day_percent
FROM
    cohort_with_quartiles
GROUP BY
    medication_complexity_quartile
ORDER BY
    medication_complexity_quartile;