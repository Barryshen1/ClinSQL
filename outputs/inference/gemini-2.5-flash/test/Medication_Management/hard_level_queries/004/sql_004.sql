WITH
-- 1. Identify all hospital admissions for female patients aged 48-58
-- and include basic demographic, admission, and DRG severity information.
EligibleDemographics AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        pat.gender,
        pat.anchor_age,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
        adm.hospital_expire_flag,
        drg.drg_severity
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.drgcodes` drg
        ON adm.hadm_id = drg.hadm_id AND drg.drg_type = 'MS-DRG' -- Focus on MS-DRG if multiple types exist
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 48 AND 58
),
-- 2. Filter for patients admitted with an acute ischemic stroke diagnosis.
-- Using both ICD-9 and ICD-10 criteria for cerebral infarction/ischemic stroke.
StrokeAdmissions AS (
    SELECT DISTINCT
        ed.subject_id,
        ed.hadm_id,
        ed.los_days,
        ed.hospital_expire_flag,
        ed.drg_severity
    FROM
        EligibleDemographics ed
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ed.hadm_id = di.hadm_id
    WHERE
        -- ICD-9 codes for ischemic stroke: 433 (Occlusion of precerebral arteries), 434 (Occlusion of cerebral arteries), 436 (Acute, but ill-defined, cerebrovascular disease)
        (di.icd_version = 9 AND (REGEXP_CONTAINS(di.icd_code, r'^433') OR REGEXP_CONTAINS(di.icd_code, r'^434') OR di.icd_code = '436'))
        OR
        -- ICD-10 codes for ischemic stroke: I63 (Cerebral infarction)
        (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^I63'))
),
-- 3. Identify, for each stroke admission, if NTI or CYP3A4 interacting drugs were prescribed.
-- NTI_DRUG_PATTERNS: Common Narrow Therapeutic Index drugs
-- CYP3A4_DRUG_PATTERNS: Common CYP3A4 inhibitors, inducers, or critical substrates
DrugExposure AS (
    SELECT
        sa.subject_id,
        sa.hadm_id,
        MAX(CASE WHEN REGEXP_CONTAINS(LOWER(p.drug), r'(digoxin|warfarin|phenytoin|carbamazepine|lithium|theophylline|cyclosporine|tacrolimus|sirolimus|gentamicin|tobramycin|amikacin|methotrexate)') THEN 1 ELSE 0 END) AS has_nti_drug,
        MAX(CASE WHEN REGEXP_CONTAINS(LOWER(p.drug), r'(clarithromycin|ketoconazole|itraconazole|ritonavir|diltiazem|verapamil|rifampin|phenytoin|carbamazepine|phenobarbital|simvastatin|atorvastatin|midazolam|alprazolam|oxycodone|fentanyl)') THEN 1 ELSE 0 END) AS has_cyp3a4_drug
    FROM
        StrokeAdmissions sa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON sa.hadm_id = p.hadm_id
    GROUP BY
        sa.subject_id, sa.hadm_id
),
-- 4. Combine all information for the final stroke patient cohort,
-- and classify them into interaction vs. control groups.
FinalStrokeCohort AS (
    SELECT
        sa.subject_id,
        sa.hadm_id,
        sa.los_days,
        sa.hospital_expire_flag,
        sa.drg_severity,
        COALESCE(de.has_nti_drug, 0) AS has_nti_drug,
        COALESCE(de.has_cyp3a4_drug, 0) AS has_cyp3a4_drug,
        CASE
            WHEN COALESCE(de.has_nti_drug, 0) = 1 AND COALESCE(de.has_cyp3a4_drug, 0) = 1
            THEN 'CYP3A4-NTI Interaction Cohort'
            ELSE 'Age-Matched Control Cohort'
        END AS cohort_group
    FROM
        StrokeAdmissions sa
    LEFT JOIN
        DrugExposure de
        ON sa.hadm_id = de.hadm_id
),
-- 5. Calculate complexity score percentiles and quartiles for the entire FinalStrokeCohort
-- (only for admissions with a valid DRG severity).
RankedStrokeCohort AS (
    SELECT
        fsc.*,
        PERCENT_RANK() OVER (ORDER BY fsc.drg_severity DESC) AS complexity_percentile_rank,
        NTILE(4) OVER (ORDER BY fsc.drg_severity DESC) AS complexity_quartile
    FROM
        FinalStrokeCohort fsc
    WHERE
        fsc.drg_severity IS NOT NULL -- Only rank patients with a valid DRG severity
)
-- Final Output
-- Part 1: Compare outcomes between the Interaction Cohort and Age-Matched Control Cohort
SELECT
    'Cohort Comparison' AS analysis_type,
    cohort_group,
    ROUND(AVG(drg_severity), 2) AS avg_complexity_score,
    ROUND(AVG(complexity_percentile_rank) * 100, 2) AS avg_complexity_percentile,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate_percent
FROM
    RankedStrokeCohort
GROUP BY
    cohort_group

UNION ALL

-- Part 2: Report LOS and mortality for stroke patients in the top quartile of complexity
SELECT
    'Top Quartile Stroke Patients' AS analysis_type,
    'Top Quartile (Complexity)' AS cohort_group,
    NULL AS avg_complexity_score, -- Not applicable for this specific output line
    NULL AS avg_complexity_percentile, -- Not applicable for this specific output line
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate_percent
FROM
    RankedStrokeCohort
WHERE
    complexity_quartile = 1 -- When ordering by DRG_severity DESC, NTILE(4) assigns 1 to the highest (top) quartile
;