with pulmonary embolism, stratify first ICU‑stay diagnostic procedure counts within 72 hours into quartiles and report N, mean procedure count, mean ICU LOS (days), and hospital mortality (%) per quartile.

Query Logic:
1. Identify admissions with a "Pulmonary embolism" diagnosis using diagnoses_icd and d_icd_diagnoses tables.
   This forms our base population of patients who *ever* had PE.
2. From these patients, filter for females aged 65-75 years old using the patients table.
3. Link these admissions to their ICU stays using the icustays table. For each subject_id,
   select only their *first* ICU stay by ordering by intime and using ROW_NUMBER().
   Also, retrieve the hospital_expire_flag from the admissions table for mortality calculation.
4. Count the number of diagnostic procedures (from procedures_icd table) for each identified
   first ICU stay. Procedures are counted if their chartdate (which is a DATE type) overlaps
   with the 72-hour window starting from icustays.intime (which is a TIMESTAMP type).
   A LEFT JOIN is used to ensure patients with zero procedures are included with a count of 0.
   The time window condition:
   - DATETIME(proc.chartdate) < TIMESTAMP_ADD(tc.intime, INTERVAL 72 HOUR): The start of the procedure day must be before the end of the 72-hour window.
   - DATETIME_ADD(DATETIME(proc.chartdate), INTERVAL 1 DAY) > tc.intime: The end of the procedure day (exclusive) must be after the start of the 72-hour window.
   This ensures that any day whose 24-hour span overlaps with the 72-hour window starting from intime is considered.
5. Assign these patients into four quartiles based on their calculated diagnostic procedure count within 72 hours, ordered ascending.
6. Finally, group the results by quartile and calculate the requested metrics:
   - N: Count of unique patients in each quartile.
   - Mean procedure count: Average of the 72-hour procedure count.
   - Mean ICU LOS: Average ICU length of stay in days.
   - Hospital mortality: Percentage of patients who died in the hospital (hospital_expire_flag = 1).
*/

WITH PulmonaryEmbolismAdmissions AS (
    -- Step 1: Identify admissions where the patient had a pulmonary embolism diagnosis.
    SELECT DISTINCT
        di.subject_id,
        di.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
        ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
    WHERE
        -- Filter for pulmonary embolism. Using LOWER() and LIKE for case-insensitivity and comprehensiveness.
        LOWER(did.long_title) LIKE '%pulmonary embolism%'
),
TargetCohortFirstICUStay AS (
    -- Step 2: Filter for female ICU patients aged 65-75 with PE diagnosis,
    -- and get their first ICU stay details including hospital mortality.
    SELECT
        p.subject_id,
        adm.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        icu.los,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        PulmonaryEmbolismAdmissions pea -- Join with PE admissions CTE
        ON adm.subject_id = pea.subject_id AND adm.hadm_id = pea.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 65 AND 75
    QUALIFY ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) = 1
),
PatientProcedureCounts AS (
    -- Step 3: Count diagnostic procedures (from procedures_icd) within the first 72 hours of the first ICU stay.
    SELECT
        tc.subject_id,
        tc.hadm_id,
        tc.stay_id,
        tc.intime,
        tc.outtime,
        tc.los,
        tc.hospital_expire_flag,
        COUNT(proc.icd_code) AS procedure_count_72h -- Count specific procedure codes
    FROM
        TargetCohortFirstICUStay tc
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
        ON tc.subject_id = proc.subject_id
        AND tc.hadm_id = proc.hadm_id
        -- Condition for procedure chartdate overlapping with the 72-hour window
        AND DATETIME(proc.chartdate) < TIMESTAMP_ADD(tc.intime, INTERVAL 72 HOUR)
        AND DATETIME_ADD(DATETIME(proc.chartdate), INTERVAL 1 DAY) > tc.intime
    GROUP BY
        tc.subject_id,
        tc.hadm_id,
        tc.stay_id,
        tc.intime,
        tc.outtime,
        tc.los,
        tc.hospital_expire_flag
),
QuartileAssignment AS (
    -- Step 4: Assign quartiles based on procedure_count_72h.
    SELECT
        *,
        NTILE(4) OVER (ORDER BY procedure_count_72h ASC) AS procedure_quartile
    FROM
        PatientProcedureCounts
)
-- Final Step: Calculate N, mean procedure count, mean ICU LOS, and mortality per quartile.
SELECT
    procedure_quartile,
    COUNT(DISTINCT subject_id) AS N_patients,
    ROUND(AVG(procedure_count_72h), 2) AS mean_72h_procedure_count,
    ROUND(AVG(los), 2) AS mean_icu_los_days,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS hospital_mortality_percent
FROM
    QuartileAssignment
GROUP BY
    procedure_quartile
ORDER BY
    procedure_quartile;