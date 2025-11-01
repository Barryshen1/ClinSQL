WITH CardiacArrestCohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        -- Calculate age at admission: anchor_age is age at anchor_year. Add difference in years.
        pts.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pts.anchor_year) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pts
        ON adm.subject_id = pts.subject_id
    WHERE
        pts.gender = 'F'
        AND (pts.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pts.anchor_year)) BETWEEN 76 AND 86
        -- Check for cardiac arrest diagnosis using ICD codes
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE
                di.hadm_id = adm.hadm_id
                AND di.icd_version IN (9, 10)
                AND (
                    (di.icd_version = 9 AND di.icd_code = '4275') -- ICD-9: Cardiac arrest
                    OR (di.icd_version = 10 AND di.icd_code LIKE 'I46%') -- ICD-10: Cardiac arrest (I46.0, I46.1, I46.2, I46.9)
                )
        )
),
-- Step 2: Calculate medication complexity score for each admission within the first 7 hospital days
MedicationComplexity AS (
    SELECT
        coh.hadm_id,
        COUNT(DISTINCT pres.gsn) AS med_complexity_score -- Counting distinct GSNs as a proxy for medication complexity
    FROM
        CardiacArrestCohort coh
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
        ON coh.hadm_id = pres.hadm_id
    WHERE
        -- Medications "active" or ordered within the first 7 days of admission
        pres.starttime BETWEEN coh.admittime AND coh.admittime + INTERVAL '7' DAY
        AND pres.gsn IS NOT NULL -- Exclude prescriptions without a GSN for complexity scoring
    GROUP BY
        coh.hadm_id
),
-- Step 3: Combine admission details with medication complexity scores, calculate readmission status, and assign quintiles
AdmissionDetailsWithScores AS (
    SELECT
        coh.subject_id,
        coh.hadm_id,
        coh.admittime,
        coh.dischtime,
        coh.hospital_expire_flag,
        COALESCE(mc.med_complexity_score, 0) AS med_complexity_score, -- Use 0 if no prescriptions found in the window
        -- Calculate the admittime of the next admission for the same patient
        LEAD(coh.admittime) OVER (PARTITION BY coh.subject_id ORDER BY coh.admittime) AS next_admittime,
        -- Assign medication complexity quintiles based on the calculated score
        NTILE(5) OVER (ORDER BY COALESCE(mc.med_complexity_score, 0)) AS complexity_quintile
    FROM
        CardiacArrestCohort coh
    LEFT JOIN
        MedicationComplexity mc
        ON coh.hadm_id = mc.hadm_id
),
-- Step 4: Final calculations for LOS and 30-day readmission flag per admission
FinalData AS (
    SELECT
        ada.subject_id,
        ada.hadm_id,
        ada.complexity_quintile,
        ada.med_complexity_score,
        TIMESTAMP_DIFF(ada.dischtime, ada.admittime, DAY) AS los_days,
        ada.hospital_expire_flag,
        CASE
            -- A 30-day readmission occurs if the next admission is within 30 days of the current discharge
            WHEN ada.next_admittime IS NOT NULL
            AND TIMESTAMP_DIFF(ada.next_admittime, ada.dischtime, DAY) <= 30 THEN 1
            ELSE 0
        END AS readmission_30_day_flag
    FROM
        AdmissionDetailsWithScores ada
)
-- Step 5: Aggregate all metrics per quintile
SELECT
    complexity_quintile,
    COUNT(DISTINCT subject_id) AS patient_count, -- Count distinct patients within each quintile
    AVG(med_complexity_score) AS avg_med_complexity_score,
    MIN(med_complexity_score) AS min_med_complexity_score,
    MAX(med_complexity_score) AS max_med_complexity_score,
    -- Length of stay metrics
    AVG(los_days) AS avg_los_days,
    MIN(los_days) AS min_los_days, 
    MAX(los_days) AS max_los_days,
    -- In-hospital mortality percentage
    AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent,
    -- 30-day readmission percentage
    AVG(readmission_30_day_flag) * 100 AS readmission_30_day_percent
FROM
    FinalData
GROUP BY
    complexity_quintile
ORDER BY
    complexity_quintile;